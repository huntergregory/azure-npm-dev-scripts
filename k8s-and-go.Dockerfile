FROM ubuntu:20.04

ARG GO_VERSION=1.16.5
ARG KUBECTL_VERSION=v1.21.1
ARG GOPATH=/go/

RUN apt-get update && DEBIAN_FRONTEND=noninteractive apt-get install -y \
    build-essential cmake curl git libffi-dev libssl-dev \
    python3 python3-pip rsync unzip wget net-tools dnsutils openssh-client vim screen  

# install go
ENV PATH "$PATH:/usr/local/go/bin:$GOPATH/bin"
RUN curl -O https://dl.google.com/go/go${GO_VERSION}.linux-amd64.tar.gz && \
    tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz && \
    rm go${GO_VERSION}.linux-amd64.tar.gz && \
    mkdir -p $GOPATH

# compile conformance test binary or use Vamsi's conformance binary
# RUN mkdir -p $GOPATH/src/k8s.io && \
#     cd $GOPATH/src/k8s.io && \
#     git clone https://github.com/kubernetes/kubernetes -b $KUBECTL_VERSION && \
#     cd kubernetes && \
#     make WHAT="test/e2e/e2e.test" 

# install kubectl
RUN curl -Lo /usr/local/bin/kubectl "https://storage.googleapis.com/kubernetes-release/release/${KUBECTL_VERSION}/bin/linux/amd64/kubectl" && \
    chmod +x /usr/local/bin/kubectl
ENV KUBECTL_PATH "/usr/local/bin/kubectl"
