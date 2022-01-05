# Terraform StaticSite on AWS

Deploy AWS Resources for Static Site by Terraform

#### Create AWS S3 Bucket for terraform state and frontend config

Create S3 Bucket named "your-terraform-config-bucket"

#### Preparation

You need below

* aws-cli >= 1.18.X
* Terraform >= 0.14.5

##### Example Installation Terraform by tfenv on mac

````bash
brew install tfenv
tfenv install 0.14.5
tfenv use 0.14.5
````

#### 1. Edit Terraform config file

Copy sample file and edit variables for your env

````bash
cd (project_root_dir)
cp terraform.tfvars.sample terraform.tfvars
vi terraform.tfvars
````

````terraform
 ...
 
route53_zone_id    = "Set your route53 zone id"
domain_static_site = "your-domain-static-site.example.com"
````

#### 2. Set AWS profile name to environment variable

````bash
export AWS_PROFILE=your-aws-profile-name
export AWS_DEFAULT_REGION="ap-northeast-1"
````

#### 3. Execute terraform init

Command Example to init

````bash
terraform init -backend-config="bucket=your-terraform-config-bucket" -backend-config="key=terraform.hoge.tfstate" -backend-config="region=ap-northeast-1" -backend-config="profile=your-aws-profile-name"
````

#### 4. Execute terraform apply

````bash
terraform apply -auto-approve -var-file=./terraform.tfvars
````



## Setup GitHub Actions for deploying static site

### Set enviroment variables

* Access to https://github.com/{your-account}/{repository-name}/settings/secrets/actions
* Push "New repository secret"
* Add Below
    * __AWS_ACCESS_KEY_ID__ : your-aws-access_key
    * __AWS_SECRET_ACCESS_KEY__ : your-aws-secret_key
    * __CLOUDFRONT_DISTRIBUTION__ : your cloudfront distribution created by terraform 
    * __S3_RESOURCE_BUCKET__: "your-domain-static-site.example.com"

####Deploy continually on pushed to git
