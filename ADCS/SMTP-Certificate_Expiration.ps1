########################################################################## 
##           Script to Monitor Certificate expiration                          
##           Author: Vikas Sukhija                            
##           Date: 08-18-2014 
##                                         
##   This scripts is used for monitor expiry dates ofcritical Certificates 
##   Alert is sent before X days of expiry 
##                                               
########################################################################## 
##########################Define Variables################################ 
 
$date1  = get-date -format "MM-dd-yyyy"  
$date1  = $date1.ToString().Replace("/","-") 
$logs   = ".\Logs" + "\" + "Processed_" + $date1 + "_.log" 
$path   = ".\logs\" 
$limit  = (Get-Date).AddDays(-60) # for log recycling 
 
Start-Transcript -Path $logs 
 
$date       = get-date 
$smtpserver = "smtp server" 
$from       = "CertExpiry@labtest.com" 
$days       = "-60" 
$errormail  = "vikass@labtest.com" 
$data       = import-csv .\CertExpiry.csv  
 
foreach($i in $data) { 
 
$CertName = $i.CertName 
$Expiry = $i.Expiry 
$AlertEmail = $i.AlertEmail 
$Type = $i.Type 
 
write-host "$CertName - $Expiry" -foregroundcolor magenta 
 
if($Expiry -eq "not set"){  
    write-host "Cert expiration date is not set for $CertName" -foregroundcolor Green  
 
    } 
 
    else 
 
    { 
    $Expiry = get-date $Expiry 
    $Expiry1 = ($Expiry).adddays($days) 
 
    if($Expiry1 -le $date){ 
 
    write-host "Cert $CertName will expire on $Expiry" -foregroundcolor red 
 
    $to1 = $AlertEmail 
    $message = new-object Net.Mail.MailMessage 
    $smtp = new-object Net.Mail.SmtpClient($smtpserver) 
    $message.From = $from 
    $message.To.Add($to1) 
    $message.bcc.ADD($errormail) 
    $message.IsBodyHtml = $False 
    $message.Subject = "Attention: Cert $CertName will expire on $Expiry - $Type" 
    $smtp.Send($message) 
    Write-host "Message Sent to $to1 for Cert $CertName" -foregroundcolor Blue 
     
        } 
    } 
} 
 
if ($error -ne $null) 
      { 
#SMTP Relay address 
$msg = new-object Net.Mail.MailMessage 
$smtp = new-object Net.Mail.SmtpClient($smtpServer) 
 
#Mail sender 
$msg.From = $from 
 
#mail recipient 
$msg.To.Add($errormail) 
$msg.Subject = "Cert expiry Script error" 
$msg.Body = $error 
$smtp.Send($msg) 
$error.clear() 
       } 
  else 
 
      { 
    Write-host "no errors till now" 
      } 
 
########################Recycle logs ###################################### 
 
Get-ChildItem -Path $path  | Where-Object {   
$_.CreationTime -lt $limit } | Remove-Item -recurse -Force  
 
Stop-Transcript 
 
##############################################################################