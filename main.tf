variable "prj_prefix" {}
variable "region_api" {}
variable "region_site" {}
variable "region_acm" {}
variable "route53_zone_id" {}
variable "domain_static_site_prd" {}
variable "domain_static_site_dev" {}

provider "aws" {
  region = var.region_api
  alias  = "api"
}

provider "aws" {
  region = var.region_site
  alias  = "site"
}

provider "aws" {
  region = var.region_acm
  alias  = "acm"
}

terraform {
  backend "s3" {
  }
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 3.74.2"
    }
  }
}

locals {
  fqdn = {
    static_site_prd = var.domain_static_site_prd
    static_site_dev = var.domain_static_site_dev
  }
  bucket = {
    static_site_prd = local.fqdn.static_site_prd
    static_site_dev = local.fqdn.static_site_dev
  }
}

### S3 for cloudfront logs
#resource "aws_s3_bucket" "accesslog_static_site" {
#  provider      = aws.site
#  bucket        = "${local.fqdn.static_site_prd}-accesslog"
#  force_destroy = true # Set true, destroy bucket with objects
#  acl           = "private"
#
#  tags = {
#    Name      = join("-", [var.prj_prefix, "s3", "accesslog_static_site"])
#    ManagedBy = "terraform"
#  }
#}

resource "aws_acm_certificate" "static_site_prd" {
  provider          = aws.acm
  domain_name       = local.fqdn.static_site_prd
  validation_method = "DNS"

  tags = {
    Name      = join("-", [var.prj_prefix, "acm_static_site_prd"])
    ManagedBy = "terraform"
  }
}
resource "aws_acm_certificate" "static_site_dev" {
  provider          = aws.acm
  domain_name       = local.fqdn.static_site_dev
  validation_method = "DNS"

  tags = {
    Name      = join("-", [var.prj_prefix, "acm_static_site_dev"])
    ManagedBy = "terraform"
  }
}

# CNAME Record
resource "aws_route53_record" "static_site_prd_acm_c" {
  for_each = {
    for d in aws_acm_certificate.static_site_prd.domain_validation_options : d.domain_name => {
      name   = d.resource_record_name
      record = d.resource_record_value
      type   = d.resource_record_type
    }
  }
  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 172800
  records         = [each.value.record]
  allow_overwrite = true
}
resource "aws_route53_record" "static_site_dev_acm_c" {
  for_each = {
    for d in aws_acm_certificate.static_site_dev.domain_validation_options : d.domain_name => {
      name   = d.resource_record_name
      record = d.resource_record_value
      type   = d.resource_record_type
    }
  }
  zone_id         = var.route53_zone_id
  name            = each.value.name
  type            = each.value.type
  ttl             = 172800
  records         = [each.value.record]
  allow_overwrite = true
}

## Related ACM Certification and CNAME record
resource "aws_acm_certificate_validation" "static_site_prd" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.static_site_prd.arn
  validation_record_fqdns = [for record in aws_route53_record.static_site_prd_acm_c : record.fqdn]
}
resource "aws_acm_certificate_validation" "static_site_dev" {
  provider                = aws.acm
  certificate_arn         = aws_acm_certificate.static_site_dev.arn
  validation_record_fqdns = [for record in aws_route53_record.static_site_dev_acm_c : record.fqdn]
}

## A record
resource "aws_route53_record" "static_site_prd_cdn_a" {
  zone_id = var.route53_zone_id
  name    = local.fqdn.static_site_prd
  type    = "A"
  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.static_site_prd.domain_name
    zone_id                = aws_cloudfront_distribution.static_site_prd.hosted_zone_id
  }
}
resource "aws_route53_record" "static_site_dev_cdn_a" {
  zone_id = var.route53_zone_id
  name    = local.fqdn.static_site_dev
  type    = "A"
  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.static_site_dev.domain_name
    zone_id                = aws_cloudfront_distribution.static_site_dev.hosted_zone_id
  }
}

# Create CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "static_site_prd" {
  comment = "Origin Access Identity for s3 ${local.bucket.static_site_prd} bucket"
}
resource "aws_cloudfront_origin_access_identity" "static_site_dev" {
  comment = "Origin Access Identity for s3 ${local.bucket.static_site_dev} bucket"
}

## Cache Policy
data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}
data "aws_cloudfront_cache_policy" "managed_caching_disabled" {
  name = "Managed-CachingDisabled"
}

## Distribution
resource "aws_cloudfront_distribution" "static_site_prd" {
  origin {
    domain_name = "${local.bucket.static_site_prd}.s3.${var.region_site}.amazonaws.com"
    origin_id   = "S3-${local.fqdn.static_site_prd}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static_site_prd.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Alternate Domain Names (CNAMEs)
  aliases = [local.fqdn.static_site_prd]

  # Config for SSL Certification
  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.static_site_prd.arn
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  retain_on_delete = false

  #logging_config {
  #  include_cookies = true
  #  bucket          = "${aws_s3_bucket.accesslog_static_site.id}.s3.amazonaws.com"
  #  prefix          = "log/static/prd/cf/"
  #}

  # For SPA to catch all request by /index.html
  custom_error_response {
    #error_caching_min_ttl = 360
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    #error_caching_min_ttl = 360
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${local.fqdn.static_site_prd}"
    #viewer_protocol_policy = "allow-all"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.managed_caching_optimized.id
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}
resource "aws_cloudfront_distribution" "static_site_dev" {
  origin {
    domain_name = "${local.bucket.static_site_dev}.s3.${var.region_site}.amazonaws.com"
    origin_id   = "S3-${local.fqdn.static_site_dev}"
    s3_origin_config {
      origin_access_identity = aws_cloudfront_origin_access_identity.static_site_dev.cloudfront_access_identity_path
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Alternate Domain Names (CNAMEs)
  aliases = [local.fqdn.static_site_dev]

  # Config for SSL Certification
  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.static_site_dev.arn
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  retain_on_delete = false

  #logging_config {
  #  include_cookies = true
  #  bucket          = "${aws_s3_bucket.accesslog_static_site.id}.s3.amazonaws.com"
  #  prefix          = "log/static/dev/cf/"
  #}

  # For SPA to catch all request by /index.html
  custom_error_response {
    #error_caching_min_ttl = 360
    error_code         = 404
    response_code      = 200
    response_page_path = "/index.html"
  }

  custom_error_response {
    #error_caching_min_ttl = 360
    error_code         = 403
    response_code      = 200
    response_page_path = "/index.html"
  }

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${local.fqdn.static_site_dev}"
    #viewer_protocol_policy = "allow-all"
    viewer_protocol_policy = "redirect-to-https"
    compress               = true
    cache_policy_id        = data.aws_cloudfront_cache_policy.managed_caching_optimized.id
    min_ttl                = 0
    default_ttl            = 3600
    max_ttl                = 86400
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }
}

# Create IAM poliocy document
data "aws_iam_policy_document" "s3_policy_static_site_prd" {
  statement {
    sid     = "PublicRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      aws_s3_bucket.static_site_prd.arn,
      "${aws_s3_bucket.static_site_prd.arn}/*"
    ]

    ## Accept to access from CloudFront only
    #principals {
    #  identifiers = [aws_cloudfront_origin_access_identity.static_site_prd.iam_arn]
    #  type        = "AWS"
    #}

    # Accept to access from All
    principals {
      identifiers = ["*"]
      type        = "*"
    }
  }
}
data "aws_iam_policy_document" "s3_policy_static_site_dev" {
  statement {
    sid     = "PublicRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      aws_s3_bucket.static_site_dev.arn,
      "${aws_s3_bucket.static_site_dev.arn}/*"
    ]

    ## Accept to access from CloudFront only
    #principals {
    #  identifiers = [aws_cloudfront_origin_access_identity.static_site_dev.iam_arn]
    #  type        = "AWS"
    #}

    # Accept to access from All
    principals {
      identifiers = ["*"]
      type        = "*"
    }
  }
}

# Related policy to bucket
resource "aws_s3_bucket_policy" "static_site_prd" {
  provider = aws.site
  bucket   = aws_s3_bucket.static_site_prd.id
  policy   = data.aws_iam_policy_document.s3_policy_static_site_prd.json
}
resource "aws_s3_bucket_policy" "static_site_dev" {
  provider = aws.site
  bucket   = aws_s3_bucket.static_site_dev.id
  policy   = data.aws_iam_policy_document.s3_policy_static_site_dev.json
}

## S3 for Static Website Hosting
resource "aws_s3_bucket" "static_site_prd" {
  provider      = aws.site
  bucket        = local.bucket.static_site_prd
  force_destroy = true # Set true, destroy bucket with objects

  acl = "private" # Accept to access from CloudFront only
  #acl = "public-read" # Accept to access to S3 Bucket from All

  #logging {
  #  target_bucket = aws_s3_bucket.accesslog_static_site.id
  #  target_prefix = "log/static/prd/s3/"
  #}

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    Name      = join("-", [var.prj_prefix, "s3", "static_site_prd"])
    ManagedBy = "terraform"
  }
}
resource "aws_s3_bucket" "static_site_dev" {
  provider      = aws.site
  bucket        = local.bucket.static_site_dev
  force_destroy = true # Set true, destroy bucket with objects

  acl = "private" # Accept to access from CloudFront only
  #acl = "public-read" # Accept to access to S3 Bucket from All

  #logging {
  #  target_bucket = aws_s3_bucket.accesslog_static_site.id
  #  target_prefix        = "log/static/dev/s3/"
  #}

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    Name      = join("-", [var.prj_prefix, "s3", "static_site_dev"])
    ManagedBy = "terraform"
  }
}

# S3 Public Access Block
# Accept to access from All
resource "aws_s3_bucket_public_access_block" "static_site_prd" {
  provider                = aws.site
  bucket                  = aws_s3_bucket.static_site_prd.bucket
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
resource "aws_s3_bucket_public_access_block" "static_site_dev" {
  provider                = aws.site
  bucket                  = aws_s3_bucket.static_site_dev.bucket
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
