[CmdletBinding()]
param(
    [Parameter(
        Position=0,
        Mandatory=$true,
        HelpMessage='Portlarını aramak istediginiz IP Adresini giriniz!')]
    [String]$IPAdres,

    [Parameter(
        Position=1,
        HelpMessage='Baslangic port numarasi(Default=1)')]
    [ValidateRange(1,65535)]
    [Int32]$SPort=1,

    [Parameter(
        Position=2,
        HelpMessage='Bitis port numarasi(Default=65535)')]
    [ValidateRange(1,65535)]
	[Int32]$FPort = 65535,
	
	[Parameter(
        Position=3,
        HelpMessage='Kullanmak istenilen thread sayisi(Default=500)')]
	[Int32]$Threads = 500
)

	$Path = "$PSScriptRoot\..\PortServisleri\ports.txt"
    $HashTable = @{ }

    foreach($Line in Get-Content -Path $Path) {
        if(-not([String]::IsNullOrEmpty($Line))) {
			try {
				$Data = $Line.Split(';')
                    
                if($Data[1] -eq "tcp") {
                        $HashTable.Add([int]$Data[0], [String]::Format($Data[2]))
                    }
                }
            catch [System.ArgumentException] { }
        }
	}
        
    if(-not(Test-Connection -IP $IPAdres -Count 2 -Quiet)) {
        throw "$IPAdres ulasilabilir degil!"
    }
	
    [System.Management.Automation.ScriptBlock]$ScriptBlock = {
        Param(
			$IPAdres,
			$Port
        )

        try{                      
            $TcpClient = New-Object System.Net.Sockets.TcpClient($IPAdres,$Port)
            
            if($TcpClient.Connected)
            {
				[pscustomobject] @{
					Port = $Port
					Protocol = "TCP"
					Status = "Open"
				}                             
                $TcpClient.Close()
            }
        }
        catch{}
    }
	
    $Runspace = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $Threads, $Host)
    $Runspace.Open()
    [System.Collections.ArrayList]$JobsList = @()
	
	foreach($Port in $SPort..$FPort)
    {
	    $ScriptParams =@{
			IPAdres = $IPAdres
			Port = $Port
		}
        $Job = [System.Management.Automation.PowerShell]::Create().AddScript($ScriptBlock).AddParameters($ScriptParams)
        $Job.RunspacePool = $Runspace
        
        $JobObject = [pscustomobject] @{
            Pipe = $Job
            Result = $Job.BeginInvoke()
        }
        [void]$JobsList.Add($JobObject)
    }
	
	$timeOut = 500
	$filePath = "$PSScriptRoot\..\XMLRaporSonuclari\file.xml"
	$XmlWriter = New-Object System.XMl.XmlTextWriter($filePath,$Null)
	$xmlWriter.Formatting = "Indented"
	$xmlWriter.WriteStartDocument()
	$xmlWriter.WriteStartElement("openports")
	$xmlWriter.WriteStartElement("IPAdres")
	$xmlWriter.WriteAttributeString("IP", $IPAdres)
	
	"'IP = $IPAdres' Adresine ait acik portlar!" | Out-File "$PSScriptRoot\..\TXTRaporSonuclari\file.txt" -Append
	
	while ($JobsList.Count -gt 0) {
		$JobProcess = $JobsList | Where-Object -FilterScript {$_.Result.IsCompleted}
		
		if($JobProcess -eq $null) {
			Start-Sleep -milli $timeOut
            continue
		}
		
		[Int32]$Counter = 0
		
        foreach($Job in $JobProcess)
        {           
            $Result = $Job.Pipe.EndInvoke($Job.Result)
            $Job.Pipe.Dispose()
			
			$JobsList.Remove($Job)
           
            if($Result.Status)
            {       
				$Counter = ($Counter + 1)
                $Service = [String]::Empty

				if($HashTable.Get_Item($Result.Port) -eq $null) {
					$Output = [pscustomobject] @{
						PORT = $Result.Port
						PROTOCOL = $Result.Protocol
						STATE = $Result.Status
						SERVICE = [String]::Format("unknown")
					}				
				}
				else {
					$Service = $HashTable.Get_Item($Result.Port).Split(';')
					$Output = [pscustomobject] @{
						PORT = $Result.Port
						PROTOCOL = $Result.Protocol
						STATE = $Result.Status
						SERVICE = $Service[0]
					}
				}
				$Output
				$xmlWriter.WriteStartElement("port")
				$xmlWriter.WriteAttributeString("no", $Output.PORT)
				$xmlWriter.WriteElementString("protocol", "tcp")
				$xmlWriter.WriteElementString("state", "open")
				$xmlWriter.WriteElementString("service", $Output.SERVICE)
				$xmlWriter.WriteEndElement()
				
				"$Counter-)$Output" | Out-File "$PSScriptRoot\..\TXTRaporSonuclari\file.txt" -Append
            }
        }
    }
	$Runspace.Close()
	$Runspace.Dispose()
	$xmlWriter.WriteEndElement()
	$xmlWriter.WriteEndElement()
	$xmlWriter.WriteEndDocument()
	$xmlWriter.Flush()
	$xmlWriter.Close()
	Rename-Item -Path "$PSScriptRoot\..\TXTRaporSonuclari\file.txt" -NewName "Rapor$(((get-date).ToUniversalTime()).ToString("yyyyMMddThhmmss")).txt"
	Rename-Item -Path "$PSScriptRoot\..\XMLRaporSonuclari\file.xml" -NewName "Rapor$(((get-date).ToUniversalTime()).ToString("yyyyMMddThhmmss")).xml"
	Write-Host("ARAMA TAMAMLANDI.`n")
