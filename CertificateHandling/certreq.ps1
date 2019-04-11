$certCN="Computer - Abcd"
$dnsName="sql01.abcd.lcl"
$caName="ldap:///CN=abcd-CA,DC=abcd,DC=lcl"

Set-Location 'Cert:\LocalMachine\My'
$cert = Get-Certificate -Template $certCN -Url $caName -DnsName $dnsName -CertStoreLocation Cert:\LocalMachine\My
$thumbprint = $cert.Certificate.Thumbprint
