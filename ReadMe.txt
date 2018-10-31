DO NOT REMOVE!
Used with FileCount MP
Reference: https://github.com/bpinoy/ManagementPacks/tree/master/File%20Count%20MP


Different parameters are added:
  ID: Must be unique per share
  Share: UNC path of the share
  Extension: The extension of the files that needs to be counted, leave empty to count all files in the share
  Count: How many files must be present for a critical state
  Time: This is the time in minutes of the maximum file age of file count
  Recurse: 0 = No need to count files in subfolders / 1 = Count also files in subfolders

File format (csv)
Id, Share, Extension, Count, Time, Recurse
1,\\dsk01.lab.lcl\software,100,, 10,0
