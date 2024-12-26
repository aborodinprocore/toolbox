provider "aws" {
  region = "us-west-2"
}

locals {
  cluster_region = "us-gov-west-1"
}

# Data source for EKS cluster information
data "aws_eks_cluster" "mgmt" {
  name = ""
}

data "aws_eks_cluster_auth" "mgmt" {
  name = ""
}

# Kubernetes provider configuration using EKS data
provider "kubernetes" {
  host                   = data.aws_eks_cluster.mgmt.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.mgmt.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.mgmt.token
}

data "aws_iam_openid_connect_provider" "eks_oidc" {
  url = data.aws_eks_cluster.mgmt.identity[0].oidc[0].issuer
}

# IAM Role for EKS Service Account
resource "aws_iam_role" "external_secrets_role" {
  name = "external-secrets-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Principal = {
          Federated = data.aws_iam_openid_connect_provider.eks_oidc.arn
        },
        Action = "sts:AssumeRoleWithWebIdentity",
        Condition = {
          StringEquals = {
            "${data.aws_iam_openid_connect_provider.eks_oidc.url}:sub" = "system:serviceaccount:external-secrets:external-secrets-sa"
            "${data.aws_iam_openid_connect_provider.eks_oidc.url}:aud" = "sts.amazonaws.com"
          }
        }
      }
    ]
  })
}

# IAM Policy for AWS Secrets Manager and Parameter Store
resource "aws_iam_policy" "secrets_manager_policy" {
  name        = "secrets-manager-policy"
  description = "Policy for accessing AWS Secrets Manager"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        "Effect" : "Allow",
        "Action" : [
          "ssm:GetParameter",
          "ssm:ListTagsForResource",
          "ssm:DescribeParameters"
        ],
        "Resource" : "*" # need to have more precise resource
      },
      {
        "Sid" : "decryptKey",
        "Effect" : "Allow",
        "Action" : [
          "kms:Decrypt"
        ],
        "Resource" : "*"
      },
      {
        Effect = "Allow",
        Action = [
          "secretsmanager:GetResourcePolicy",
          "secretsmanager:GetSecretValue",
          "secretsmanager:DescribeSecret",
          "secretsmanager:ListSecretVersionIds"
        ],
        Resource = "*" # need to have more precise resource
        # Resource = "arn:aws-us-gov:secretsmanager:us-gov-west-1:210250638747:secret:/production/*"
      }
    ]
  })
}
resource "aws_iam_policy" "parameter_store_policy" {
  name        = "parameter-store-policy"
  description = "Policy for accessing AWS Parameter Store"

  policy = jsonencode({
    Version = "2012-10-17",
    Statement = [
      {
        Effect = "Allow",
        Action = [
          "ssm:GetParameter",
          "ssm:ListTagsForResource",
          "ssm:DescribeParameters"
        ],
        Resource = "*" # need to have more precise resource
      }
    ]
  })
}

# Attach policy to role
resource "aws_iam_role_policy_attachment" "attach_secrets_manager_policy" {
  role       = aws_iam_role.external_secrets_role.name
  policy_arn = aws_iam_policy.secrets_manager_policy.arn
}

resource "aws_iam_role_policy_attachment" "attach_parameter_store_policy" {
  role       = aws_iam_role.external_secrets_role.name
  policy_arn = aws_iam_policy.parameter_store_policy.arn
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.mgmt.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.mgmt.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.mgmt.token
  }
}
resource "helm_release" "external_secrets" {
  name             = "external-secrets"
  chart            = "external-secrets"
  namespace        = "external-secrets"
  create_namespace = true

  # Use the Helm Chart repository
  repository = "https://charts.external-secrets.io"
  version    = "v0.12.1"


  # Additional values
  values = [
    yamlencode({
      serviceAccount = {
        name = "external-secrets-sa"
        annotations = {
          "eks.amazonaws.com/role-arn" = aws_iam_role.external_secrets_role.arn
        }
      }
    })
  ]
}

# resource "kubernetes_manifest" "aws_secretsmanager_secretstore" {
#   depends_on = [helm_release.external_secrets]
#   manifest = {
#     apiVersion = "external-secrets.io/v1beta1"
#     kind       = "SecretStore"
#     metadata = {
#       name      = "aws-secretsmanager"
#       namespace = "external-secrets"
#     }
#     spec = {
#       provider = {
#         aws = {
#           service = "SecretsManager"
#           region  = "us-west-2"
#           auth = {
#             jwt = {
#               serviceAccountRef = {
#                 name = "external-secrets-sa"
#                 namespace = "external-secrets"
#               }
#             }
#           }
#         }
#       }
#     }
#   }
# }

# resource "kubernetes_manifest" "aws_parameterstore_secretstore" {
#   depends_on = [helm_release.external_secrets]
#   manifest = {
#     apiVersion = "external-secrets.io/v1beta1"
#     kind       = "SecretStore"
#     metadata = {
#       name      = "aws-parameterstore"
#       namespace = "external-secrets"
#     }
#     spec = {
#       provider = {
#         aws = {
#           service = "ParameterStore"
#           region  = "us-west-2"
#           auth = {
#             jwt = {
#               serviceAccountRef = {
#                 name = "external-secrets-sa"
#                 namespace = "external-secrets"
#               }
#             }
#           }
#         }
#       }
#     }
#   }
# }