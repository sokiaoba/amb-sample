# a script to initizalize ec2 for AMB client
# use this like
#   ./init-amb.sh {NETWORK_ID} {MEMBER_ID} {CA_ENDPOINT}

# https://docs.aws.amazon.com/managed-blockchain/latest/managementguide/get-started-create-client.html
# 

NETWORK_ID=$1
MEMBER_ID=$2
CA_ENDPOINT=$3
ADMIN_USERNAME=$4
ADMIN_PASSWORD=$5

# doker
sudo yum update -y
sudo yum install -y telnet
sudo yum -y install emacs
sudo yum install -y docker
sudo service docker start
sudo usermod -a -G docker ec2-user

# doker-compose
sudo curl -L https://github.com/docker/compose/releases/download/1.20.0/docker-compose-`uname -s`-`uname -m` -o /usr/local/bin/docker-compose
sudo chmod a+x /usr/local/bin/docker-compose
sudo yum install libtool -y

# golang
wget https://dl.google.com/go/go1.10.3.linux-amd64.tar.gz
tar -xzf go1.10.3.linux-amd64.tar.gz
sudo mv go /usr/local
sudo yum install libtool-ltdl-devel -y
sudo yum install git -y

# bash_profile
cat << 'EOS' > ~/.bash_profile
# Get the aliases and functions
if [ -f ~/.bashrc ]; then
  . ~/.bashrc
fi
# User specific environment and startup programs
PATH=$PATH:$HOME/.local/bin:$HOME/bin
# GOROOT is the location where Go package is installed on your system
export GOROOT=/usr/local/go
# GOPATH is the location of your work directory
export GOPATH=$HOME/go
# Update PATH so that you can access the go binary system wide
export PATH=$GOROOT/bin:$PATH
export PATH=$PATH:/home/ec2-user/go/src/github.com/hyperledger/fabric-ca/bin
export PATH
EOS

# awscli
pip install --upgrade --user awscli
aws configure

# amb
aws managedblockchain get-member \
    --network-id ${NETWORK_ID} \
    --member-id ${MEMBER_ID}

curl https://${CA_ENDPOINT}/cainfo -k

# fabric-ca-client
go get -u github.com/hyperledger/fabric-ca/cmd/...
cd /home/ec2-user/go/src/github.com/hyperledger/fabric-ca
git fetch
git checkout release-1.2
make fabric-ca-client

# clone the samples repository
cd /home/ec2-user
git clone https://github.com/hyperledger/fabric-samples.git

# docker-compose-cli.yaml 
touch docker-compose-cli.yaml 
cat << 'EOS' > ~/docker-compose-cli.yaml 
version: '2'
services:
  cli:
    container_name: cli
    image: hyperledger/fabric-tools:1.2.0
    tty: true
    environment:
      - GOPATH=/opt/gopath
      - CORE_VM_ENDPOINT=unix:///host/var/run/docker.sock
      - CORE_LOGGING_LEVEL=info # TODO: Set logging level to debug for more verbose logging
      - CORE_PEER_ID=cli
      - CORE_CHAINCODE_KEEPALIVE=10
    working_dir: /opt/gopath/src/github.com/hyperledger/fabric/peer
    command: /bin/bash
    volumes:
      - /var/run/:/host/var/run/
      - /home/ec2-user/fabric-samples/chaincode:/opt/gopath/src/github.com/
      - /home/ec2-user:/opt/home
EOS

docker-compose -f docker-compose-cli.yaml up -d

# create the certificate file
aws s3 cp s3://us-east-1.managedblockchain/etc/managedblockchain-tls-chain.pem  /home/ec2-user/managedblockchain-tls-chain.pem
openssl x509 -noout -text -in /home/ec2-user/managedblockchain-tls-chain.pem

# enroll the administrative user
fabric-ca-client enroll \
    -u https://${ADMIN_USERMNAME}:${ADMIN_PASSWORD}@${CA_ENDPOINT} \
    --tls.certfiles /home/ec2-user/managedblockchain-tls-chain.pem -M /home/ec2-user/admin-msp

# copy certificates for the msp
cp -r admin-msp/signcerts admin-msp/admincerts
