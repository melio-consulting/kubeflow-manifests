locals {


  use_static = "static" == var.pipeline_s3_credential_option
  use_irsa   = "irsa" == var.pipeline_s3_credential_option


}

resource "kubernetes_namespace" "kubeflow" {
  metadata {
    labels = {
      control-plane   = "kubeflow"
      istio-injection = "enabled"
    }

    name = "kubeflow"
  }
}

data "aws_iam_role" "pipeline_irsa_iam_role" {
  count      = local.use_static ? 0 : 1
  name       = try(module.kubeflow_pipeline_irsa[0].irsa_iam_role_name, null)
  depends_on = [module.kubeflow_pipeline_irsa]
}

data "aws_iam_role" "user_namespace_irsa_iam_role" {
  count      = local.use_static ? 0 : 1
  name       = try(module.user_namespace_irsa[0].irsa_iam_role_name, null)
  depends_on = [module.user_namespace_irsa]
}

module "kubeflow_pipeline_irsa" {
  count                             = local.use_static ? 0 : 1
  source                            = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.32.1"
  kubernetes_namespace              = kubernetes_namespace.kubeflow.metadata[0].name
  create_kubernetes_namespace       = false
  create_kubernetes_service_account = false
  kubernetes_service_account        = "ml-pipeline"
  irsa_iam_role_name                = format("%s-%s-%.22s-%.16s", "ml-pipeline", "irsa", var.addon_context.eks_cluster_id, var.addon_context.aws_region_name)
  irsa_iam_policies                 = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  irsa_iam_role_path                = var.addon_context.irsa_iam_role_path
  irsa_iam_permissions_boundary     = var.addon_context.irsa_iam_permissions_boundary
  eks_cluster_id                    = var.addon_context.eks_cluster_id
  eks_oidc_provider_arn             = var.addon_context.eks_oidc_provider_arn
}

module "user_namespace_irsa" {
  count                             = local.use_static ? 0 : 1
  source                            = "github.com/aws-ia/terraform-aws-eks-blueprints//modules/irsa?ref=v4.32.1"
  kubernetes_namespace              = "kubeflow-user-example-com"
  create_kubernetes_namespace       = false
  create_kubernetes_service_account = false
  kubernetes_service_account        = "default-editor"
  irsa_iam_role_name                = format("%s-%s-%.22s-%.16s", "user-namespace", "irsa", var.addon_context.eks_cluster_id, var.addon_context.aws_region_name)
  irsa_iam_policies                 = ["arn:aws:iam::aws:policy/AmazonS3FullAccess"]
  irsa_iam_role_path                = var.addon_context.irsa_iam_role_path
  irsa_iam_permissions_boundary     = var.addon_context.irsa_iam_permissions_boundary
  eks_cluster_id                    = var.addon_context.eks_cluster_id
  eks_oidc_provider_arn             = var.addon_context.eks_oidc_provider_arn
}

module "s3" {
  count                          = var.use_s3 ? 1 : 0
  source                         = "../../../../iaac/terraform/aws-infra/s3"
  force_destroy_bucket           = var.force_destroy_s3_bucket
  minio_aws_access_key_id        = var.minio_aws_access_key_id
  minio_aws_secret_access_key    = var.minio_aws_secret_access_key
  secret_recovery_window_in_days = var.secret_recovery_window_in_days
  tags                           = var.tags
}

module "kubeflow_issuer" {
  source = "../../../../iaac/terraform/common/kubeflow-issuer"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/kubeflow-issuer"
  }

  addon_context = var.addon_context
  depends_on    = [kubernetes_namespace.kubeflow]
}

module "kubeflow_istio" {
  source = "../../../../iaac/terraform/common/istio"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/istio"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_issuer]
}

module "kubeflow_dex" {
  source = "../../../../iaac/terraform/common/dex"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/dex"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_istio]
}

module "kubeflow_oidc_authservice" {
  source = "../../../../iaac/terraform/common/oidc-authservice"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/oidc-authservice"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_dex]
}

module "kubeflow_knative_serving" {
  source = "../../../../iaac/terraform/common/knative-serving"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/knative-serving"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_oidc_authservice]
}

module "kubeflow_cluster_local_gateway" {
  source = "../../../../iaac/terraform/common/cluster-local-gateway"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/cluster-local-gateway"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_knative_serving]
}

module "kubeflow_knative_eventing" {
  source = "../../../../iaac/terraform/common/knative-eventing"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/knative-eventing"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_cluster_local_gateway]
}

module "kubeflow_roles" {
  source = "../../../../iaac/terraform/common/kubeflow-roles"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/kubeflow-roles"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_knative_eventing]
}

module "kubeflow_istio_resources" {
  source = "../../../../iaac/terraform/common/kubeflow-istio-resources"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/kubeflow-istio-resources"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_roles]
}

module "filter_kfp_set_values" {
  source = "../../../../iaac/terraform/utils/set-values-filter"
  set_values = {
    "s3.bucketName"         = try(module.s3[0].s3_bucket_name, null),
    "s3.minioServiceRegion" = coalesce(var.minio_service_region, var.addon_context.aws_region_name)
    "s3.minioServiceHost"   = var.minio_service_host
    "s3.roleArn"            = try(data.aws_iam_role.pipeline_irsa_iam_role[0].arn, null)
  }
}

module "kubeflow_pipelines" {
  source = "../../../../iaac/terraform/apps/kubeflow-pipelines"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/kubeflow-pipelines/s3-only"
    set   = module.filter_kfp_set_values.set_values
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_istio_resources, module.kubeflow_pipeline_irsa]
}

module "kubeflow_kserve" {
  source = "../../../../iaac/terraform/common/kserve"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/kserve"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_pipelines]
}

module "kubeflow_models_web_app" {
  source = "../../../../iaac/terraform/apps/models-web-app"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/models-web-app"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_kserve]
}

module "kubeflow_katib" {
  source = "../../../../iaac/terraform/apps/katib"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/katib/vanilla"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_models_web_app]
}

module "kubeflow_central_dashboard" {
  source = "../../../../iaac/terraform/apps/central-dashboard"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/central-dashboard"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_katib]
}

module "kubeflow_admission_webhook" {
  source = "../../../../iaac/terraform/apps/admission-webhook"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/admission-webhook"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_central_dashboard]
}

module "kubeflow_notebook_controller" {
  source = "../../../../iaac/terraform/apps/notebook-controller"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/notebook-controller"
    set = [
      {
        name  = "cullingPolicy.cullIdleTime",
        value = var.notebook_cull_idle_time
      },
      {
        name  = "cullingPolicy.enableCulling",
        value = var.notebook_enable_culling
      },
      {
        name  = "cullingPolicy.idlenessCheckPeriod",
        value = var.notebook_idleness_check_period
      }
    ]
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_admission_webhook]
}

module "kubeflow_jupyter_web_app" {
  source = "../../../../iaac/terraform/apps/jupyter-web-app"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/jupyter-web-app"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_notebook_controller]
}

module "kubeflow_profiles_and_kfam" {
  source = "../../../../iaac/terraform/apps/profiles-and-kfam"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/profiles-and-kfam"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_jupyter_web_app]
}

module "kubeflow_volumes_web_app" {
  source = "../../../../iaac/terraform/apps/volumes-web-app"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/volumes-web-app"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_profiles_and_kfam]
}

module "kubeflow_tensorboards_web_app" {
  source = "../../../../iaac/terraform/apps/tensorboards-web-app"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/tensorboards-web-app"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_volumes_web_app]
}

module "kubeflow_tensorboard_controller" {
  source = "../../../../iaac/terraform/apps/tensorboard-controller"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/tensorboard-controller"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_tensorboards_web_app]
}

module "kubeflow_training_operator" {
  source = "../../../../iaac/terraform/apps/training-operator"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/apps/training-operator"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_tensorboard_controller]
}

module "kubeflow_aws_telemetry" {
  count  = var.enable_aws_telemetry ? 1 : 0
  source = "../../../../iaac/terraform/common/aws-telemetry"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/aws-telemetry"
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_training_operator]
}

module "filter_kubeflow_user_namespace_set_values" {
  source = "../../../../iaac/terraform/utils/set-values-filter"
  set_values = {
    "awsIamForServiceAccount.awsIamRole" = try(data.aws_iam_role.user_namespace_irsa_iam_role[0].arn, null)
  }
}

module "kubeflow_user_namespace" {
  source = "../../../../iaac/terraform/common/user-namespace"
  helm_config = {
    chart = "${var.kf_helm_repo_path}/charts/common/user-namespace",
    set   = module.filter_kubeflow_user_namespace_set_values.set_values
  }
  addon_context = var.addon_context
  depends_on    = [module.kubeflow_aws_telemetry, module.user_namespace_irsa]
}

module "ack_sagemaker" {
  source        = "../../../../iaac/terraform/common/ack-sagemaker-controller"
  addon_context = var.addon_context
}
