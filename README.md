# Lanuch kubernetes cluster using footloose and kubeadm

## prerequisites
- Install docker 
- Install footloose 


## Lanuch your cluster
- Create a seperate docker network if it is not create
```shell script
docker network create footloose-cluster
```
- Run the script that provisions the cluster
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
