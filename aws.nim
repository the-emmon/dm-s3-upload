## Insert credentials into the two "creds" string fields (AccessKey/SecretKey), replace "BUCKETNAME".
## Compile with 'nim c --opt:speed -d:ssl -d:release --app:console aws.nim'
## Binary size can be reduced from 573k to 189k with 'strip aws && upx --best --strip-relocs=0 aws'
import nimaws/s3client, httpclient, os, asyncdispatch, strformat
var
  client:S3Client
  creds:(string,string)
creds = ("ACCESSKEY", "SECRETKEY") ## CREDS GO HERE
client = newS3Client(creds, "us-east-2") ## Replace us-east-2 if another location is used.

proc up(upload:string): Future[string] {.async.} = ## Replaceall "BUCKETHERE" with your bucket name
  try:
    discard waitFor client.put_object("BUCKETHERE", upload, readFile(upload)) ## Do upload
  except: ## Something didn't work out. Retry a few times before officially failing
    var (dir, name, ext) = splitFile(upload) ## Grabbing filename for fmt"" debug echoes
    echo fmt"Upload failed for {name}{ext}."
    echo "Retrying in 3s..."
    sleep(3000) ## In ms
    try:
      discard waitFor client.put_object("BUCKETHERE", upload, readFile(upload))
    except:
      echo "Upload failed again!"
      echo fmt"Hopefully the network will bounce back. Retrying {name}{ext} in 15s..."
      sleep(15000)
      try:
        discard waitFor client.put_object("BUCKETHERE", upload, readFile(upload))
      except:
        echo "Uh oh... things aren't going so great. Initializing the upload client and trying one last time."
        sleep(4000)
        var client2 = newS3Client(creds, "us-east-2") ## Hopefully you never hit this, but switch out location here
        sleep(1000)
        try:
          discard waitFor client.put_object("BUCKETHERE", upload, readFile(upload))
        except:
          echo fmt"FAILED TO UPLOAD {name}{ext}! Check network connection & credentials."
          quit()
  var (dir, name, ext) = splitFile(upload)
  return fmt"Successfully uploaded {name}{ext}!"

var count = 0
for file in walkDirRec("./data"): ## Uploads contents of folder "data", located in the same directory, recursively.
  discard up($file)
  count += 1
echo fmt"Done. Uploaded {$count} files."

## Tried a lot of different tactics for this one: synchronous, asynchronous, threading, zip upload w/ Lambda to unzip,
## Nim to dirwalk + python's boto3 for uploads, and alternate versions written in both Crystal and Ruby.
## This Nim async script won; for the provided fileset, this script clocked the quickest consistently valid upload.
## I initially thought that multithreading, which has worked well for me in the past, would be a speedier approach.
## However, even two parallel upload threads was enough to zap my xfinity internet connection.
## KC's Fiber might be able to bear it, but I chose not to take the risk since the monothread upload runs quickly.
