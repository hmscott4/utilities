$certCN="sql01.abcd.lcl"
$serviceAccount="abcd\SqlService"

$WorkingCert = Get-ChildItem CERT:\LocalMachine\My |where {$_.Subject -match $certCN}

$TPrint = $WorkingCert.Thumbprint
$rsaFile = $WorkingCert.PrivateKey.CspKeyContainerInfo.UniqueKeyContainerName

$keyPath = "C:\ProgramData\Microsoft\Crypto\RSA\MachineKeys\"
$fullPath=$keyPath+$rsaFile
$acl=Get-Acl -Path $fullPath
$permission=$serviceAccount,"Read","Allow"
$accessRule=new-object System.Security.AccessControl.FileSystemAccessRule $permission
$acl.AddAccessRule($accessRule)
Try 
{
 Set-Acl $fullPath $acl
  "        Success: ACL set on certificate"
}
Catch
{
  "        Error: unable to set ACL on certificate"
	Exit
}