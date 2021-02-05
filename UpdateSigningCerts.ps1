param ($stsFQDN)
if ($stsFQDN -eq $null) {
    $stsFQDN = read-host -Prompt "Please enter the STS FQDN" 
}
#Grab the current STS1 signing certificates from metadata
$url = "https://"+$stsfqdn+"/federationmetadata/2007-06/federationmetadata.xml"

Write-Host Gathering ADFS Metadata... -nonewline
try{
    $metadata = Invoke-RestMethod -Uri $url -TimeoutSec 5
}catch{
    Write-Host Unable to connect to $url -ForegroundColor Red
}

#extract signing certificates from metadata
if($metadata){
    Write-host Done -foregroundcolor green
    $metadataexchangeuri=$metadata.EntityDescriptor.RoleDescriptor.securitytokenserviceendpoint.endpointreference.metadata.metadata.metadatasection.metadatareference.address.'#text'
    $stscerts = $metadata.ChildNodes.spssodescriptor.KeyDescriptor
    $stssigningcerts = foreach ($stscert in $stscerts){if($stscert.use -eq "signing"){$stscert}}
    $stssigningcerts = $stssigningcerts|foreach {$_.keyinfo.x509data.x509certificate}
    
    $error.Clear()
    #connect to tenant
    Write-host Connecting to MSOL... -nonewline
    Try{
       Connect-MsolService -ErrorAction Stop
    }catch{
        write-host Failed to connect for the following reason -  $error[0] -foregroundcolor Red
    } 

    if (!$error){
        Write-host Connected -foregroundcolor green
        #Get the current signing certs on the federated trust
        do{
            $error.clear()
            $domain = Read-Host -Prompt "Enter federated domain name (ex. mail.mil)"
            $federationsettings = Get-MsolDomainFederationSettings -DomainName $domain -erroraction silentlycontinue
            if($error){write-host $error[0] -foregroundcolor Red}
        }until($error[0].exception -notmatch "This domain does not exist. Check the name and try again.")

        if ($federationsettings -ne $null -and $federationsettings.MetadataExchangeUri -match $metadataexchangeuri){
            $fedsigningcert = $federationsettings.signingcertificate
            $fednextsigningcert = $federationsettings.nextsigningcertificate
            $results = @()
            $results += $stssigningcerts -contains $fedsigningcert
            $results += $stssigningcerts -contains $fednextsigningcert

            if ($stssigningcerts.count -gt 1){
                if ($results -contains $false){
                    Write-host ADFS Signing certificates are not up to date in Azure AD -ForegroundColor Yellow
                    #prompts to update certs
                    $a = new-object -ComObject wscript.shell
                    $answer = $a.popup("Do you want update the signing certificates in Azure AD to match ADFS?", 0,"Update Signing certs",4)
                    if($answer -eq 6){
                    $error.clear()
                        Try{
                            Write-Host Updating federated $domain signing certificates... -NoNewline
                            $update = Set-MsolDomainFederationSettings -DomainName $domain -SigningCertificate $stssigningcerts[0] -NextSigningCertificate $stssigningcerts[1] -ErrorAction Stop
                            if(!$error){Write-Host $domain has been updated -ForegroundColor Green}
                        }catch{Write-host Failed to update $domain -ForegroundColor Red}
                    }

                }else{
                    Write-Host ADFS Signing certificates are up to date in Azure AD -ForegroundColor Green
                }
            }else{
                if ($results -contains $true){
                    Write-Host ADFS Signing certificates are up to date in Azure AD -ForegroundColor Green
                }else{
                    Write-host ADFS Signing certificates are not up to date in Azure AD -ForegroundColor Yellow
                    #prompts to update certs
                    $a = new-object -ComObject wscript.shell
                    $answer = $a.popup("Do you want update the signing certificates in Azure AD to match ADFS?", 0,"Update Signing certs",4)
                    if($answer -eq 6){
                        $error.clear()
                        Try{
                            Write-Host Updating federated $domain signing certificates... -NoNewline
                            $update = Set-MsolDomainFederationSettings -DomainName $domain -SigningCertificate $stssigningcerts -ErrorAction Stop
                            if(!$error){Write-Host $domain has been updated -ForegroundColor Green}
                        }catch{Write-host Failed to update $domain - $error[0] -ForegroundColor Red}
                    }
                }
            }
        }elseif($federationsettings -eq $null){
            Write-host Federation settings were not found running Get-MsolDomainFederationSettings -ForegroundColor Yellow
        }else{
            Write-host Determined that the federated domain $domain is not currently linked to $metadata.EntityDescriptor.entityID -ForegroundColor Yellow
        }
    }
}