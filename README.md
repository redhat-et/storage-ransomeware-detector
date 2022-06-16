# Object Storage Ransomware Detector

## Background

This is a demo of the Open Source Summit NA 2022 session: "Let Your Cloud Native Storage Save You from Ransomware!" - Yuval Lifshitz and Huamin Chen, Red Hat.

## Install

Start [minikube](https://minikube.sigs.k8s.io/docs/start/) with an extra disk for Ceph:

```console
minikube start --driver=kvm2 --cpus=8 --extra-disks=1
```

Deploy Ceph using the [Rook operator](https://rook.io/docs/rook/v1.9/Getting-Started/quickstart/):

```console
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/crds.yaml
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/common.yaml
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/operator.yaml
```

Now the "test" (single node) Ceph cluster (note that we are using a custom build of Ceph for some of the lua features):

```console
kubectl apply -f cluster-test.yaml
```

And make sure that the OSDs and MONs are up and running:

```console
kubectl -n rook-ceph get pod
```

Then, the "test" (single node) object store:

```console
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/object-test.yaml
```

And last the "toolbox" pod, needed for uploading the lua scripts (since lua is not part of Rook yet):

```console
kubectl apply -f https://raw.githubusercontent.com/rook/rook/master/deploy/examples/toolbox.yaml
```

> Note that since Rook support only Ceph "quincy" and my developer build is from Ceph "reef", you would need to run these two commands manually for the object store to run:
``` console
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd pool create .rgw.root 32 32 --yes_i_really_mean_it
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- ceph osd pool application enable .rgw.root rgw
```

## Test Setup

Once we have everything up and running, we use the toolbox pod to upload 2 [lua scripts](https://docs.ceph.com/en/latest/radosgw/lua-scripting/) to the RGW:

* in the "pre request" context we are going to do the quarantine:

```console
TOOLS_POD=$(kubectl get pod -n rook-ceph -l app=rook-ceph-tools -o jsonpath="{.items[0].metadata.name}")
kubectl cp ./quarantine.lua $POD:/home/rook -n rook-ceph
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- radosgw-admin script put --infile=/home/rook/quarantine.lua --context=preRequest
```

* in the "data" context we are going to perform the ransomware detection:

```console
kubectl cp ./ransomware.lua $POD:/home/rook -n rook-ceph
kubectl -n rook-ceph exec -it deploy/rook-ceph-tools -- radosgw-admin script put --infile=/home/rook/ransomware.lua --context=data
```

we can create 2 buckets. The 1st would be the regular one and the 2nd would be the one we use for quarantine.
We would use Rook's [Object Bucket Claim](https://rook.io/docs/rook/v1.9/ceph-object-bucket-claim.html) for that:

```console
kubectl apply -f obc-with-quarantine.yaml
```

Add a new NodePort service and attach it to the Object Store (for external access):

```console
kubectl apply -f rgw-service.yaml
```

And expose it to the machine running the minikube VM:

```console
export AWS_URL=$(minikube service --url rook-ceph-rgw-my-store-external -n rook-ceph)
```

Get the user credentials:

```console
export AWS_ACCESS_KEY_ID=$(kubectl -n default get secret home -o jsonpath='{.data.AWS_ACCESS_KEY_ID}' | base64 --decode)
export AWS_SECRET_ACCESS_KEY=$(kubectl -n default get secret home -o jsonpath='{.data.AWS_SECRET_ACCESS_KEY}' | base64 --decode)
```

## Test

Create a directory called "home", should contain a variety of files: text, pdf, jpeg, png, mp3, mp4, docx, pptx, zip, etc.
We will upload the content of the "home" directory to the RGW:

```console
aws aws --endpoint-url "$AWS_URL" s3 cp home s3://home/
```

Then run the `wannacry.sh` script to have encrypted version of the files in the "enc-home" directory:

```console
./wannacry.sh home enc-home
```

And finally upload the content of the "enc-home" directory to RGW and see when our lua script detect the encryption.


```console
aws aws --endpoint-url "$AWS_URL" s3 cp enc-home s3://home/
```

Check the RGW log to see that the lua script detected the ransomware and activated quarantine.

```console
kubectl logs -l app=rook-ceph-rgw -n rook-ceph --tail 100
```

And more important, verify that the new objects were indeed quarantines:

```console
aws --endpoint-url "$AWS_URL" s3 ls s3://home
aws --endpoint-url "$AWS_URL" s3 ls s3://home-quarantine
```

