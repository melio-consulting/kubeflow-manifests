### Kubeflow on AWS

We make sure of the Kubeflow on AWS deployment of kubeflow (https://awslabs.github.io/kubeflow-manifests/). We have our own fork and branch containing the highwind cluster deployment: see https://github.com/melio-consulting/kubeflow-manifests/tree/highwind-deployment

1. Clone our fork and ensure you are on the `highwind-deployment` branch:
    - `git clone --branch highwind-deployment https://github.com/melio-consulting/kubeflow-manifests`

2. From within the kubeflow-manifests repo, navigate into the `deployments/highwind/terraform` directory of the https://github.com/melio-consulting/kubeflow-manifests repo.
    - `cd deployments/highwind/terraform`

3. Copy the `backend.tf`, `assume_role.sh`, and `sample.auto.tfvars` into the `deployments/highwind/terraform` directory of the https://github.com/melio-consulting/kubeflow-manifests repo. Chat to highwind team for this.

4. The process for deployment is then as follows from within the `deployments/highwind/terraform` directory of the https://github.com/melio-consulting/kubeflow-manifests repo:
    1. `source assume_role.sh` in order to assume the deployment IAM role
    2. `terraform init -reconfigure`
    3. `terraform plan`
    4. Use `make deploy` to run the deployment
        - `make delete` is used to tear down the deployment
        - see the makefile for more detail