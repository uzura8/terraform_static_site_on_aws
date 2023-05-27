# Terraform StaticSite on AWS

Deploy AWS Resources for Static Site by Terraform

#### Create AWS S3 Bucket for terraform state and frontend config

Create S3 Bucket named "your-terraform-config-bucket"

#### Preparation

You need below

* aws-cli >= 1.27.X
* Terraform >= 1.4.6

##### Example Installation Terraform by tfenv on mac

```bash
brew install tfenv
tfenv install 1.4.6
tfenv use 1.4.6
```

#### 1. Edit Terraform config file

Copy sample file and edit variables for your env

```bash
cd (project_root_dir)
cp terraform.tfvars.sample terraform.tfvars
vi terraform.tfvars
```

```terraform
prj_prefix = "your-porject-name"
region_api = "ap-northeast-1"
region_site = "ap-northeast-1"
region_acm = "us-east-1"
route53_zone_id = "Set your route53 zone id"
domain_static_site_prd = "your-domain-static-site.example.com"
domain_static_site_dev = "your-domain-static-site-dev.example.com"
```

#### 2. Set AWS profile name to environment variable

```bash
export AWS_PROFILE=your-aws-profile-name
export AWS_REGION="ap-northeast-1"
```

#### 3. Execute terraform init

Command Example to init

```bash
terraform init -backend-config="bucket=your-deployment" -backend-config="key=terraform/your-project/terraform.tfstate" -backend-config="region=ap-northeast-1" -backend-config="profile=your-aws-profile-name"
```

#### 4. Execute terraform apply

```bash
terraform apply -auto-approve -var-file=./terraform.tfvars
```

## Setup GitHub Actions for deploying static site

### Set enviroment variables

* Access to https://github.com/{your-account}/{repository-name}/settings/secrets/actions
* Push "New repository secret"
* Add Below
  - Common
    - **AWS_ACCESS_KEY_ID** : your-aws-access_key
    - **AWS_SECRET_ACCESS_KEY** : your-aws-secret_key
  - For Production
    - **CLOUDFRONT_DISTRIBUTION** : your cloudfront distribution created by terraform for production
    - **S3_CONFIG_BUCKET**: "your-serverles-configs/your-project/frontend/prd" for production
    - **S3_RESOURCE_BUCKET**: "your-domain-static-site.example.com" for production
  - For Develop
    - **CLOUDFRONT_DISTRIBUTION_DEV** : your cloudfront distribution created by terraform for develop
    - **S3_CONFIG_BUCKET_DEV**: "your-serverles-configs/your-project/frontend/dev" for develop
    - **S3_RESOURCE_BUCKET_DEV**: "your-domain-static-site-dev.example.com" for develop

#### Deploy continually on pushed to git
