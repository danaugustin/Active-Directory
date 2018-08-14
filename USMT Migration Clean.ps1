#Start as elevated user
#Run this from legacy DC (AWHDC)
#TODO - Move variables from inside invoke-command to outside local scope using $using: command.

#Define Machines
#TODO - Setup CSV File import
$machines = @(
LIST
)

#USMT Settings

$USMTFilesPath = "c:\tools"

Start-Transcript

foreach ($pc in $machines){
    #Check connectivity to machine
    $test_connect = try {test-wsman -ErrorAction SilentlyContinue $pc}catch{}
    if (-not $test_connect) {
        write-host "Cannot connect to $pc - Skipping"
        continue
    }

    #Run Command to backup profile. 
    #Copy USMT and password files to remote machine
    write-host "Copying USMT and password files to $pc"
    Copy-Item -Path $USMTFilesPath -Destination "\\$pc\C$\" -ErrorAction Stop -Recurse -force
    Invoke-Command -ComputerName $pc -ScriptBlock {
        $USMTPath = "c:\tools\amd64"
        $networkServer = "NAME"
        $networkShare = "ProfileBackups"
        $migrationXML = "/i:`"$USMTPath\migdocs.xml`""
        $loglevel = "4"
        $profile = $ENV:COMPUTERNAME
        if (test-path \\$networkServer\$networkShare\$ENV:COMPUTERNAME){
            write-host "Profile already exists - Skipping Step"
            continue
        }
        Write-Host "`nBeginning migration with the following configuration:`n" `
        "Destination: \\$networkServer\$networkShare\$profile`n" `
        "========================================================="
        write-host "Starting USMT with PATH "
        write-host "`"$USMTPath\SCANSTATE.EXE`""
        Start-Process "`"$USMTPath\SCANSTATE.EXE`"" -ArgumentList "`"\\$networkServer\$networkShare\$profile`" /c /vsc $migrationXML /l:`"\\$networkServer\$networkShare\$profile\SAVESTATE.log`" /all /localonly /v:$loglevel" -Wait -NoNewWindow
    }
    #remove USMTtemp
    write-host "Removing USMT from $pc"
    Remove-Item \\$pc\C$\tools\amd64 -Force -Recurse

    #Switch domains on PC and clean profiles
    write-host "Running domain migration on $pc"
    Invoke-Command -ComputerName $pc -ScriptBlock {
        #Check to ensure the computer isn't already on the target domain
        if ((Get-WmiObject Win32_ComputerSystem).Domain -notlike 'NEW.DOMAIN') {
            write-host "Computer is already on Target Domain - Skipping Step"
            continue
        }
        #add local user
        write-host "Adding USER Administrator Account"
        net user /add USER PASS
        net localgroup administrators USER /add
        #Domain Join Variables
        $username_joinTarget=â€aiwhc.local\administratorâ€
        $aeskey=get-content â€œc:\tools\aeskey.txtâ€
        $password_joinTarget=get-content â€œc:\tools\credpassword.txtâ€|convertto-securestring -key $aeskey
        $cred_JoinTarget=new-object -typename System.Management.Automation.PSCredential â€“argumentlist $username_joinTarget,$password_joinTarget
        $Error.clear
        #Join target domain 
        Try {Add-Computer -DomainName aiwhc.local -Credential $cred_JoinTarget -PassThru -Verbose}
        Catch {return $false}
        Start-Sleep -Seconds 10
        
        #Remove Domain profiles using WMI
        write-host "Removing domain profiles on $ENV:COMPUTERNAME"
        write-host "Checking to ensure profiles are backed up.."
        $networkServer = "SERVER"
        $networkShare = "ProfileBackups"
        if (test-path \\$networkServer\$networkShare\$ENV:COMPUTERNAME){
            write-host "Profile is backed up - Moving on.."
            'Total number of profiles before removal -- {0}' -f (Get-WmiObject -class Win32_UserProfile | Measure-Object).Count
            Get-WMIObject -class Win32_UserProfile | foreach {
                write-host "removing $_.LocalPath"
                $_.Delete()
            }
            'Total number of profiles after clean up -- {0}' -f (Get-WmiObject -class Win32_UserProfile | Measure-Object).Count
        } else {
            write-host "Profile missing - Skipping step"
            continue
        }
        write-host "Rebooting $ENV:COMPUTERNAME"
        restart-computer -force
    }

    write-host "Finished processing $pc"
}
Stop-Transcript