variable "prj_prefix" {}
variable "aws_region" {}
variable "route53_zone_id" {}
variable "domain_static_site" {}

provider "aws" {
}

provider "aws" {
  region = "us-east-1"
  alias  = "virginia"
}

terraform {
  backend "s3" {
  }
}

locals {
  fqdn = {
    static_site = var.domain_static_site
  }
  bucket = {
    name = local.fqdn.static_site
  }
}

## S3 for cloudfront logs
resource "aws_s3_bucket" "s3_accesslog" {
  bucket = "${local.fqdn.static_site}-s3-accesslog"
  acl    = "log-delivery-write"

  tags = {
    Name      = join("-", [var.prj_prefix, "s3", "s3_accesslog"])
    ManagedBy = "terraform"
  }
}
resource "aws_s3_bucket" "cf_accesslog" {
  bucket = "${local.fqdn.static_site}-cf-accesslog"
  acl    = "private"

  tags = {
    Name      = join("-", [var.prj_prefix, "s3", "cf_accesslog"])
    ManagedBy = "terraform"
  }
}

## Cache Policy
data "aws_cloudfront_cache_policy" "managed_caching_optimized" {
  name = "Managed-CachingOptimized"
}
data "aws_cloudfront_cache_policy" "managed_caching_disabled" {
  name = "Managed-CachingDisabled"
}

## Distribution
resource "aws_cloudfront_distribution" "main" {
  origin {
    ## Accept to access from CloudFront only
    #domain_name = "${local.bucket.name}.s3-${var.aws_region}.amazonaws.com"

    # Accept to access to S3 Bucket from All
    domain_name = aws_s3_bucket.app.website_endpoint

    origin_id = "S3-${local.fqdn.static_site}"

    ## Accept to access from CloudFront only
    #s3_origin_config {
    #  origin_access_identity = aws_cloudfront_origin_access_identity.main.cloudfront_access_identity_path
    #}

    # Accept to access to S3 Bucket from All
    custom_origin_config {
      http_port                = 80
      https_port               = 443
      origin_keepalive_timeout = 10
      origin_protocol_policy   = "match-viewer"
      origin_read_timeout      = 60
      origin_ssl_protocols = [
        "TLSv1",
        "TLSv1.1",
        "TLSv1.2"
      ]
    }
  }

  enabled             = true
  is_ipv6_enabled     = true
  default_root_object = "index.html"

  # Alternate Domain Names (CNAMEs)
  aliases = [local.fqdn.static_site]

  # Config for SSL Certification
  viewer_certificate {
    cloudfront_default_certificate = false
    acm_certificate_arn            = aws_acm_certificate.main.arn
    minimum_protocol_version       = "TLSv1.2_2021"
    ssl_support_method             = "sni-only"
  }

  retain_on_delete = false

  logging_config {
    include_cookies = true
    bucket          = "${aws_s3_bucket.cf_accesslog.id}.s3.amazonaws.com"
    prefix          = "log/"
  }

  ## For SPA to catch all request by /index.html
  #custom_error_response {
  #  #error_caching_min_ttl = 360
  #  error_code         = 404
  #  response_code      = 200
  #  response_page_path = "/index.html"
  #}
  #
  #custom_error_response {
  #  #error_caching_min_ttl = 360
  #  error_code         = 403
  #  response_code      = 200
  #  response_page_path = "/index.html"
  #}

  default_cache_behavior {
    allowed_methods  = ["GET", "HEAD", "OPTIONS"]
    cached_methods   = ["GET", "HEAD"]
    target_origin_id = "S3-${local.fqdn.static_site}"
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

resource "aws_acm_certificate" "main" {
  provider          = aws.virginia
  domain_name       = local.fqdn.static_site
  validation_method = "DNS"

  tags = {
    Name      = join("-", [var.prj_prefix, "acm"])
    ManagedBy = "terraform"
  }
}

# CNAME Record
resource "aws_route53_record" "main_acm_c" {
  for_each = {
    for d in aws_acm_certificate.main.domain_validation_options : d.domain_name => {
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
resource "aws_acm_certificate_validation" "main" {
  provider                = aws.virginia
  certificate_arn         = aws_acm_certificate.main.arn
  validation_record_fqdns = [for record in aws_route53_record.main_acm_c : record.fqdn]
}

## A record
resource "aws_route53_record" "main_cdn_a" {
  zone_id = var.route53_zone_id
  name    = local.fqdn.static_site
  type    = "A"
  alias {
    evaluate_target_health = true
    name                   = aws_cloudfront_distribution.main.domain_name
    zone_id                = aws_cloudfront_distribution.main.hosted_zone_id
  }
}

# Create CloudFront OAI
resource "aws_cloudfront_origin_access_identity" "main" {
  comment = "Origin Access Identity for s3 ${local.bucket.name} bucket"
}

# Create IAM poliocy document
data "aws_iam_policy_document" "s3_policy" {
  statement {
    sid     = "PublicRead"
    effect  = "Allow"
    actions = ["s3:GetObject"]
    resources = [
      aws_s3_bucket.app.arn,
      "${aws_s3_bucket.app.arn}/*"
    ]

    ## Accept to access from CloudFront only
    #principals {
    #  identifiers = [aws_cloudfront_origin_access_identity.main.iam_arn]
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
resource "aws_s3_bucket_policy" "main" {
  bucket = aws_s3_bucket.app.id
  policy = data.aws_iam_policy_document.s3_policy.json
}

## S3 for Static Website Hosting
resource "aws_s3_bucket" "app" {
  bucket = local.bucket.name

  #force_destroy = false # Set true, destroy bucket with objects

  #acl = "private" # Accept to access from CloudFront only
  #acl = "public-read" # Accept to access to S3 Bucket from All

  logging {
    target_bucket = aws_s3_bucket.s3_accesslog.id
    target_prefix = "log/"
  }

  website {
    index_document = "index.html"
    error_document = "error.html"
  }

  tags = {
    Name      = join("-", [var.prj_prefix, "s3", "app"])
    ManagedBy = "terraform"
  }
}

# S3 Public Access Block
# Accept to access from All
resource "aws_s3_bucket_public_access_block" "app" {
  bucket                  = aws_s3_bucket.app.bucket
  block_public_acls       = false
  block_public_policy     = false
  ignore_public_acls      = false
  restrict_public_buckets = false
}
