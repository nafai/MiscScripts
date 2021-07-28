# Joel Roth 2021

# With thanks to the comment left by "grubi" on https://michlstechblog.info/blog/windows-run-task-scheduler-task-as-limited-user/

param(
	[Parameter(Mandatory=$true)]
	[string]$TargetTaskName = "MyTask Name"
)

if ($TargetTaskName -match "^(?<Folder>.*\\)?(?<Task>[^\\\r\n]+)$")
{
    $FolderName = $Matches."Folder"
    $TaskName = $Matches."Task"
    write-host "Folder: $FolderName"
    write-host "TaskName: $TaskName"
}
else
{
    Throw "Could not parse task name: $TargetTaskName"
}
 
$scheduler = New-Object -ComObject "Schedule.Service"
$scheduler.Connect()
$task = $scheduler.GetFolder($FolderName).GetTask($TaskName)
$sec = $task.GetSecurityDescriptor(0xF)
 
$sec = $sec + "(A;;GRGX;;;AU)" # Authenticated Users - Read and Run
$task.SetSecurityDescriptor($sec, 0)
