docker run --name aelf-node --restart always \
    -d -p 6801:6801 -p 8000:8000 -p 5001:5001 -p 5011:5011 \
    --platform linux/amd64 \
    --ulimit core=-1 \
    --security-opt seccomp=unconfined --privileged=true \
    -it gldeng/aelf-groth16-10