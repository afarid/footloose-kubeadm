# Lanuch kubernetes cluster using footloose and kubeadm

## prerequisites
- Install docker 
- Install footloose 

## Lanuch you cluster
```shell script
./start.sh
```

## verify
```shell script
footloose ssh root@master0 "kubectl get nodes"
```
## Destroy 
```shell script
footloose delete
```
