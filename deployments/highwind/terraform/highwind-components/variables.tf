variable "kf_helm_repo_path" {
  description = "Full path to the location of the helm folder to install from for KF 1.6"
  type        = string
}

variable "addon_context" {
  description = "Input configuration for the addon"
  type = object({
    aws_caller_identity_account_id = string
    aws_caller_identity_arn        = string
    aws_eks_cluster_endpoint       = string
    aws_partition_id               = string
    aws_region_name                = string
    eks_cluster_id                 = string
    eks_oidc_issuer_url            = string
    eks_oidc_provider_arn          = string
    tags                           = map(string)
    irsa_iam_role_path             = string
    irsa_iam_permissions_boundary  = string
  })
}

variable "enable_aws_telemetry" {
  description = "Enable AWS telemetry component"
  type        = bool
  default     = true
}


variable "use_s3" {
  type    = bool
  default = true
}

variable "pipeline_s3_credential_option" {
  description = "The credential type to use to authenticate KFP to use S3. One of [irsa, static]"
  type        = string
  default     = "irsa"

  validation {
    condition     = "irsa" == var.pipeline_s3_credential_option || "static" == var.pipeline_s3_credential_option
    error_message = "The pipeline_s3_credential_option must be one of [irsa, static]"
  }
}

variable "minio_service_region" {
  type        = string
  default     = null
  description = "S3 service region. Change this field if the S3 bucket will be in a different region than the EKS cluster"
}

variable "minio_service_host" {
  type        = string
  default     = "s3.amazonaws.com"
  description = "S3 service host DNS. This field will need to be changed when making requests from other partitions e.g. China Regions"
}

variable "force_destroy_s3_bucket" {
  type        = bool
  description = "Destroys s3 bucket even when the bucket is not empty"
  default     = false
}

variable "secret_recovery_window_in_days" {
  type    = number
  default = 7
}

variable "minio_aws_access_key_id" {
  type        = string
  description = "AWS access key ID to authenticate minio client"
  default     = null
}

variable "minio_aws_secret_access_key" {
  type        = string
  description = "AWS secret access key to authenticate minio client"
  default     = null
}


variable "notebook_enable_culling" {
  description = "Enable Notebook culling feature. If set to true then the Notebook Controller will scale all Notebooks with Last activity older than the notebook_cull_idle_time to zero"
  type        = string
  default     = false
}

variable "notebook_cull_idle_time" {
  description = "If a Notebook's LAST_ACTIVITY_ANNOTATION from the current timestamp exceeds this value then the Notebook will be scaled to zero (culled). ENABLE_CULLING must be set to 'true' for this setting to take effect.(minutes)"
  type        = string
  default     = 30
}

variable "notebook_idleness_check_period" {
  description = "How frequently the controller should poll each Notebook to update its LAST_ACTIVITY_ANNOTATION (minutes)"
  type        = string
  default     = 5
}

variable "tags" {
  description = "Additional tags (e.g. `map('BusinessUnit`,`XYZ`)"
  type        = map(string)
  default     = {}
}