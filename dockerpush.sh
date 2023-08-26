#!/bin/bash

cd ..
docker build -t $2.dkr.ecr.us-east-1.amazonaws.com/web-repo:latest .

aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin $2.dkr.ecr.us-east-1.amazonaws.com
docker push $2.dkr.ecr.us-east-1.amazonaws.com/web-repo:latest

#$2=aws account number
