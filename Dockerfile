FROM alpine:3.18

# 1. Install Core Dependencies
RUN apk add --no-cache \
    bash \
    curl \
    git \
    jq \
    python3 \
    py3-pip \
    docker-cli

# 2. Install Terraform (Fixed Version)
RUN curl -SL https://releases.hashicorp.com/terraform/1.7.0/terraform_1.7.0_linux_amd64.zip -o terraform.zip && \
    unzip terraform.zip && mv terraform /usr/local/bin/ && rm terraform.zip

# 3. Install Kubectl & Helm
RUN curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl" && \
    chmod +x kubectl && mv kubectl /usr/local/bin/
RUN curl https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

# 4. Install AWS CLI
RUN apk add --no-cache aws-cli

# 5. Set Workdir
WORKDIR /workspace
COPY . .
chmod +x ./scripts/hypernova

ENTRYPOINT ["./scripts/hypernova"]