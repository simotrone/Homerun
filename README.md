Homerun is a Mojolicious::Lite webapp to manage upload/download file with simple
interface and little archive.


### Config

- *storage_dir*  for the directory that holds files
- *upload_limit* in bytes (eg: 5*1024*1024)
- *file_limit*   max number of files in the storage_dir
- *secret*       secret to secure my sessions
- *basename*     default filename when someone download the file

