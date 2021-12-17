<#
    Script: HAProxy Tanzu Deployment
    Author: M. Buijs
    Original concept developed by: William Lam - https://github.com/lamw/vmware-scripts/blob/master/powershell/deploy_3nic_haproxy.ps1
    version: 1.0 - 2021-12-17
    Execution: HAProxy_Deployment.ps1
#>

# Set variables

	# Script variables
	$global:script_name = "HAProxy_Tanzu_Deployment"
	$global:script_version = "v1.0"
	$global:debug = 0
    $global:temp_directory = "C:\Temp\"

    # vSphere
    $vCenter = "LAB-VC01.Lab.local"
    $ClusterName = "Lab"
    $DatastorePrefix = "iSCSI - Production - *" # datastore prefix
    $DiskProvisioning = "thin" # thin or thick
    $Hardware = "v14" # Virtual hardware

    # HAProxy General
    $HAProxyDisplayName = "LAB-HAProxy01"
    $HAProxyHostname = "lab-haproxy01.lab.local"
    $HAProxyDNS = "192.168.126.21, 192.168.126.22"
    $HAProxyPort = "5556" # 5556 default port

    # HAProxy Management
    $HAProxyManagementNetwork = "Management"
    $HAProxyManagementIPAddress = "192.168.151.40/24" # Format is IP Address/CIDR Prefix
    $HAProxyManagementGateway = "192.168.151.254"

    # HAProxy Frontend
    $HAProxyFrontendNetwork = "TKG - Frontend"
    $HAProxyFrontendIPAddress = "192.168.127.40/24" # Format is IP Address/CIDR Prefix
    $HAProxyFrontendGateway = "192.168.27.254"
    $HAProxyLoadBalanceIPRange = "192.168.127.128/26" # Format is Network CIDR Notation

    # HAProxy Workload
    $HAProxyWorkloadNetwork = "TKG - Workload"
    $HAProxyWorkloadIPAddress = "192.168.128.40/24" # Format is IP Address/CIDR Prefix
    $HAProxyWorkloadGateway = "192.168.128.254"

    # HAProxy Users
    $HAProxyUsername = "haproxy_api"

# Functions
function banner {
    # Clear
	Clear-Host

	# Clear errors
	$Error.clear()

    # Message
    Write-Host "`n---------------------------------------------------------" -foreground Red
    Write-Host "               $script_name - $script_version" -foreground Red
    Write-Host "---------------------------------------------------------" -foreground Red
}

function script_exit {
	Write-Host -Foreground Yellow ""
	Write-Host -Foreground Yellow "ERROR Message: $($Error[0].Exception.Message)"
	Write-Host -Foreground Yellow ""
	Write-Host -Foreground Cyan "Exiting PowerShell Script..."
	exit
}

function validate_media {
    ##### Message
    Write-Host "`nValidating media:"

        #### Locate temp directory
        If (-not (Test-Path "$($Temp_Directory)")) {
            Write-Host -ForegroundColor Red "- The temp directory is not created ($Temp_Directory)"
            script_exit
        }
        else {
            Write-Host -ForegroundColor Green "- Located the temp directory ($Temp_Directory)"
        }

        #### Locate OVA file
        Try {
            Write-Host -ForegroundColor Green  "- Searching for OVA file"
            $script:OVF_HAProxy = $(Get-ChildItem -Path "$Temp_Directory" -Include haproxy-v*.ova -File -Recurse -ErrorAction Stop | Sort-Object LastWriteTime | Select-Object -last 1)

            ### In case of no results
            if ([string]::IsNullOrEmpty($OVF_HAProxy.name)) {
                throw
            }
            #### Message
            Write-Host -ForegroundColor Green "- Located HAProxy OVA file ($($OVF_HAProxy.Name))"
        }
        Catch {
            Write-Host -ForegroundColor Red  "- Could not find HAProxy OVA file in location ($Temp_Directory)"
            script_exit
        }
}

function ask_passwords {
    # Banner
    Write-Host "`nPasswords:"

    # Ask passwords
    $script:HAProxyOSPassword = Read-Host -asSecureString "- Enter the HAProxy user password (root)"
    $script:HAProxyPassword = Read-Host -asSecureString "- Enter the HAProxy user password ($HAProxyUsername)"

    # Validation
    If ($HAProxyOSPassword.Length -eq 0) {
        Write-Host -ForegroundColor Red "- HAProxy root account password is empty"
        script_exit
    }
    # Validation
    If ($HAProxyPassword.Length -eq 0) {
        Write-Host -ForegroundColor Red "- HAProxy user account password is empty"
        script_exit
    }
}

function connect_vcenter {
    # Banner
    Write-Host "`nvCenter connection:"

        # Disable vCenter deprecation warnings
        Set-PowerCLIConfiguration -DisplayDeprecationWarnings $false -Confirm:$false | Out-Null

        # Disable vCenter certification errors
        Set-PowerCLIConfiguration -InvalidCertificateAction "ignore" -Confirm:$false | Out-Null

        # Determine script or user input
        if ($vCenter) {
            Write-Host -ForegroundColor Green "- Connecting with vCenter server ($vCenter)"
        }
        else {
            # Ask required vCenter information
            $script:vCenter = Read-Host "- Enter the vCenter IP address or hostname"
        }

        if ($global:DefaultVIServers.Count -gt 0) {
            Write-Host -ForegroundColor Green "- Session already established ($vCenter)"
        }
        else {
            # Check IP address for connectivity
            if (test-connection -computername $vCenter -count 1 -quiet -ErrorAction SilentlyContinue) {
                Write-Host -ForegroundColor Green "- Host is alive ($vCenter)"
            }
            else {
                Write-Host -ForegroundColor Red "- Host is not responding ($vCenter)"
                $vCenter = ""
                Break
            }

            # Connect with vCenter
            try {
                Write-host -ForegroundColor Green "- Connecting to vCenter, please wait..."

                # Connect to vCenter
                Connect-ViServer -server $vCenter -ErrorAction Stop | Out-Null
            }
            catch [Exception]{
                $status = 1
                $exception = $_.Exception
                Write-Host "- Could not connect to vCenter, exiting script" -foreground Yellow
                Write-Host ""
                Write-Host "Exit code: $status" -foreground Yellow
                Write-Host "Output: $exception" -foreground Yellow
                Break
            }
        }

        # Message
        Write-Host -ForegroundColor Green "- Connection successful"
}

function ovf_config {
    # Banner
    Write-Host "`nOVF Configuration:"

    # Start
    Write-Host -ForegroundColor Green "- Creating OVF Configuration"

    $script:ovfconfig = Get-OvfConfiguration $OVF_HAProxy

    # Three nic configuration
    $script:ovfconfig.DeploymentOption.value = "frontend"

    # General
    $script:ovfconfig.network.hostname.value = $HAProxyHostname
    $script:ovfconfig.network.nameservers.value = $HAProxyDNS
    $script:ovfconfig.loadbalance.dataplane_port.value = $HAProxyPort

    # Network port groups
    $script:ovfconfig.NetworkMapping.Management.value = $HAProxyManagementNetwork
    $script:ovfconfig.NetworkMapping.Frontend.value = $HAProxyFrontendNetwork
    $script:ovfconfig.NetworkMapping.Workload.value = $HAProxyWorkloadNetwork

    # Management
    $script:ovfconfig.network.management_ip.value = $HAProxyManagementIPAddress
    $script:ovfconfig.network.management_gateway.value = $HAProxyManagementGateway

    # Workload
    $script:ovfconfig.network.workload_ip.value = $HAProxyWorkloadIPAddress
    $script:ovfconfig.network.workload_gateway.value = $HAProxyWorkloadGateway
    $script:ovfconfig.loadbalance.service_ip_range.value = $HAProxyLoadBalanceIPRange

    # Accounts
    $script:ovfconfig.loadbalance.haproxy_user.value = $HAProxyUsername

    # Password root
    $BSTR1 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HAProxyOSPassword)
    $HAProxyOSPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR1)
    $script:ovfconfig.appliance.root_pwd.value = $HAProxyOSPassword

    # Password user
    $BSTR2 = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($HAProxyPassword)
    $HAProxyPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR2)
    $script:ovfconfig.loadbalance.haproxy_pwd.value = $HAProxyPassword

    # Finish
    Write-Host -ForegroundColor Green "- Completed OVF Configuration"
}

function pre_deployment {
    # Banner
    Write-Host "`nPre-deployment:"

    # Cluster
    $script:Cluster = Get-Cluster $ClusterName
    Write-Host -ForegroundColor Green "- Selected cluster ($Cluster)"

    # VMhost
    $script:VMHost = Get-VMHost | Where-Object { $_.ConnectionState -eq "Connected" } | Get-Random
    Write-Host -ForegroundColor Green "- Selected ESXi Host ($VMHost)"

    # Datastore
    $script:Datastore = Get-VMhost -Name $VMHost | Get-Datastore -Name $DatastorePrefix | Select-Object Name, FreeSpaceGB | Sort-Object FreeSpaceGB -Descending | Select-Object -first 1 | Select-Object Name -expandproperty name
    Write-Host -ForegroundColor Green "- Selected datatore ($Datastore)"

    # Check virtual machine name exists
    $VMname_check_query = Get-Cluster -Name $ClusterName | Get-VM -name $HAProxyDisplayName -ErrorAction SilentlyContinue

    if (! $VMname_check_query) {
        Write-Host -ForegroundColor Green "- Virtual machine name is not in use ($HAProxyDisplayName)"
    }
    else {
        Write-Host -ForegroundColor Red "- Virtual Machine with name ($HAProxyDisplayName) already exists. Exiting script cannot continue!"
        script_exit
    }

	#### Ask for conformation
	Write-Host "`nThis task is going to build the HAProxy virtual machine for TKGs."
	$confirmation = Read-Host "Are you sure you want to proceed? [y/n]"

	if ($confirmation -eq 'n') {
		Write-Host "Operation cancelled by user!" -Foreground Red
		base_exit
	}

	if (!$confirmation) {
		Write-Host -Foreground Red "No input detected!"
	    base_exit
	}
}

function deployment {
    # Banner
    Write-Host "`nDeployment:"

	# HAProxy deployment of OVF
	try {
		### Message
		Write-Host -ForegroundColor Green "- Starting HAProxy Deployment ($HAProxyHostname / $HAProxyManagementIPAddress)"

        $script:vm = Import-VApp -Source $OVF_HAProxy -OvfConfiguration $ovfconfig -Name $HAProxyDisplayName -Location $Cluster -VMHost $VMHost -Datastore $Datastore -DiskStorageFormat $DiskProvisioning

        ### Message
		Write-Host -ForegroundColor Green "- Finished HAProxy Deployment ($HAProxyHostname / $HAProxyManagementIPAddress)"
    }
	catch [Exception]{
		Write-Host -ForegroundColor Red "- HAProxy Deployment Failed ($HAProxyHostname / $HAProxyManagementIPAddress)"
		script_exit
	}
}

function post_deployment {
    # Banner
    Write-Host "`nPost-deployment:"

	# Configure OVF
	try {
		### Message
		Write-Host -ForegroundColor Green "- Starting HAProxy OVF Configuration ($HAProxyHostname / $HAProxyManagementIPAddress)"

        $vappProperties = $vm.ExtensionData.Config.VAppConfig.Property
        $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec

        $ovfChanges = @{
            "frontend_ip"=$HAProxyFrontendIPAddress
            "frontend_gateway"=$HAProxyFrontendGateway
        }

        ### Message
		Write-Host -ForegroundColor Green "- Finished HAProxy OVF Configuration ($HAProxyHostname / $HAProxyManagementIPAddress)"
    }
	catch {
		Write-Host -ForegroundColor Red "- HAProxy OVF Configuration failed ($HAProxyHostname / $HAProxyManagementIPAddress)"
		script_exit
	}

    try {
        # Message
		Write-Host -ForegroundColor Green "- Starting HAProxy Update Specification ($HAProxyHostname / $HAProxyManagementIPAddress)"

        # Retrieve existing OVF properties from VM
        $vappProperties = $VM.ExtensionData.Config.VAppConfig.Property

        # Create a new Update spec based on the # of OVF properties to update
        $spec = New-Object VMware.Vim.VirtualMachineConfigSpec
        $spec.vAppConfig = New-Object VMware.Vim.VmConfigSpec
        $propertySpec = New-Object VMware.Vim.VAppPropertySpec[]($ovfChanges.count)

        # Find OVF property Id and update the Update Spec
        foreach ($vappProperty in $vappProperties) {
            if($ovfChanges.ContainsKey($vappProperty.Id)) {
                $tmp = New-Object VMware.Vim.VAppPropertySpec
                $tmp.Operation = "edit"
                $tmp.Info = New-Object VMware.Vim.VAppPropertyInfo
                $tmp.Info.Key = $vappProperty.Key
                $tmp.Info.value = $ovfChanges[$vappProperty.Id]
                $propertySpec+=($tmp)
            }
        }
        $spec.VAppConfig.Property = $propertySpec

        # Message
		Write-Host -ForegroundColor Green "- Finished HAProxy Update Specification ($HAProxyHostname / $HAProxyManagementIPAddress)"
    }

    catch {
        # Message
        Write-Host -ForegroundColor Red "- HAProxy Update Specification failed ($HAProxyHostname / $HAProxyManagementIPAddress)"
		script_exit
    }

    # HAProxy reconfigure task for virtual machine
    try {
        # Message
        Write-Host -ForegroundColor Green "- Start Reconfigure VM task ($HAProxyHostname / $HAProxyManagementIPAddress)"
        $task = $vm.ExtensionData.ReconfigVM_Task($spec)
        $task1 = Get-Task -Id ("Task-$($task.value)")
        $task1 | Wait-Task | Out-Null
    }
    catch {
        Write-Host -ForegroundColor Red "- Reconfigure VM task failed ($HAProxyHostname / $HAProxyManagementIPAddress)"
        script_exit
    }

    # Message
    Write-Host -ForegroundColor Green "- Completed the reconfigure VM task ($HAProxyHostname / $HAProxyManagementIPAddress)"
}

function boot {
    # Banner
    Write-Host "`nBoot:"

	# Upgrade Virtual Hardware
	Try {
		Write-Host -ForegroundColor Green "- Upgrade Virtual Hardware ($HAProxyHostname / $HAProxyManagementIPAddress)";
		Get-VM -Name $vm | Set-VM -Version $Hardware -Confirm:$false | Out-Null
	}
	Catch {
		Write-Host -ForegroundColor Red "- Upgrade Virtual Hardware failed ($HAProxyHostname / $HAProxyManagementIPAddress)";
		script_exit
	}

	# Power-On Virtual Machine
	Try {
		Write-Host -ForegroundColor Green "- Power-on HAProxy started ($HAProxyHostname / $HAProxyManagementIPAddress)"
		Get-VM $vm | Start-VM | Out-Null
	}
	Catch {
		Write-Host -ForegroundColor Red "- Starting HAProxy failed ($HAProxyHostname / $HAProxyManagementIPAddress)"
		script_exit
	}

    Write-Host -ForegroundColor Green "- Power-on HAProxy completed ($HAProxyHostname / $HAProxyManagementIPAddress)"
}

function check {
    # Banner
    Write-Host "`nCheck:"

    # Set total of retries
    $TOTAL = "10"

    # Host retry interval (seconds)
	$HOST_WAIT = "10";

    # Start loop
    For ($i=0; $i -le $TOTAL; $i++) {

        # Number conversion to 2 digit:
        $NUMBER = [INT]$i + 1
        $NUMBER = "{0:D2}" -f $NUMBER

        # Check Host
        $Host_check_query = Test-Connection -computername $HAProxyHostname -count 1 -quiet -ErrorAction SilentlyContinue

        # Validate, else retry after a wait
        if ($Host_check_query -eq $false) {
            Write-Host -Foregroundcolor green "- [$NUMBER/$TOTAL] Checking HAProxy availability ($HAProxyHostname)"
            Start-Sleep $HOST_WAIT
        }
        else {
            Write-Host -Foregroundcolor green "- [$NUMBER/$TOTAL] Checking HAProxy availability ($HAProxyHostname)"
            Write-Host -Foregroundcolor green "- [Ready] HAProxy is available ($HAProxyHostname)"
            break
        }
    }
}

function retrieve_certificate {
    # Banner
    Write-Host "`nRetrieve certificate:"

    # Build URL
    $script:url = "https://${HAProxyHostname}:${HAProxyPort}/v2/info"

    # Configure local system
    try {
        # Message
        Write-Host -ForegroundColor Green "- Disable certificate checking on local system"

        # Disable certificate check
        [System.Net.ServicePointManager]::ServerCertificateValidationCallback = {$true}
    }
	catch {
		Write-Host -ForegroundColor Red "- Could not disable certificate checking on local system"
		script_exit
	}

    # Download certificate
    try {
        # Message
        Write-Host -ForegroundColor Green "- Get HAProxy certificate ($url)"

        $req = [Net.HttpWebRequest]::Create($url)
        $req.ServicePoint | Out-Null

        # Authentication
        $req.Credentials = New-Object Net.NetworkCredential($HAProxyUsername, $HAProxyPassword);
    }
	catch {
		Write-Host -ForegroundColor Red "- Could not get HAProxy Certificate ($url)"
		script_exit
	}

    # Store error messages in variable to not crash a try and catch statement.
    $GetResponseResult = $req.GetResponse()

    # Store certificate as X.509 file
    try {
        # Message
        Write-Host -ForegroundColor Green "- Store HAProxy certificate as X.509 ($url)"

        $cert = $req.ServicePoint.Certificate
        $bytes = $cert.Export([Security.Cryptography.X509Certificates.X509ContentType]::Cert)
        set-content -value $bytes -encoding byte -path "$pwd\$HAProxyHostname.cer"
    }
    catch {
        Write-Host -ForegroundColor Red "- HAProxy X.509 certificate could not be saved ($url)"
        Write-Host -ForegroundColor Red "- Result from GetResponse: ($GetResponseResult)";
        script_exit
    }

    # Convert certificate to Base-64 file
    try {
        # Message
        Write-Host -ForegroundColor Green "- Store HAProxy certificate as Base-64 ($url)"

        $InsertLineBreaks=1
        $sMyCert="$pwd\$HAProxyHostname.cer"
        $oMyCert = New-Object System.Security.Cryptography.X509Certificates.X509Certificate2($sMyCert)
        $oPem = New-Object System.Text.StringBuilder
        $oPem.AppendLine("-----BEGIN CERTIFICATE-----") | Out-Null
        $oPem.AppendLine([System.Convert]::ToBase64String($oMyCert.RawData,$InsertLineBreaks)) | Out-Null
        $oPem.AppendLine("-----END CERTIFICATE-----") | Out-Null
        $oPem.ToString() | out-file "$pwd\$HAProxyHostname.pem"
    }
    catch {
        Write-Host -ForegroundColor Red "- HAProxy Base-64 certificate could not be saved ($url)"
        script_exit
    }
}

function complete_banner {
    # Message
    Write-Host -ForegroundColor Green "- HAProxy deployment completed successfully! ($HAProxyHostname / $HAProxyManagementIPAddress)"
}

##### Main
banner
validate_media
connect_vcenter
ask_passwords
ovf_config
pre_deployment
deployment
post_deployment
boot
check
retrieve_certificate
complete_banner