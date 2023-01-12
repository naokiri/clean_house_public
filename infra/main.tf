terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 4.49"
    }
  }

  # Depends on my terraform-github-setup
  backend "s3" {
    bucket = "iwakiri.infra"
    key    = "terraform/clean_house_infra"
    region = "ap-northeast-1"
  }

  required_version = ">= 0.14.9"
}

provider "aws" {
  profile = "default"
  region  = "ap-northeast-1"

  assume_role {
    role_arn = "arn:aws:iam::399923773482:role/TerraformGithubApplyRole"
  }
}

resource "aws_apigatewayv2_api" "clean_record" {
  name          = "clean_record"
  protocol_type = "HTTP"

  tags = {
    project = "clean_house"
  }
}

#unittest_resource "aws_apigatewayv2_api_mapping" "clean_record_mapping" {
#  api_id      = aws_apigatewayv2_api.clean_record.id
#  domain_name = aws_apigatewayv2_domain_name.clean_record.id
#  stage       = aws_apigatewayv2_stage.clean_record.id
#}


resource "aws_apigatewayv2_route" "clean_house_route" {
  api_id             = aws_apigatewayv2_api.clean_record.id
  route_key          = "POST /record/{actionID}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.clean_house_auth.id
  operation_name     = "Record"
  target             = "integrations/${aws_apigatewayv2_integration.clean_house_integration.id}"
}

resource "aws_apigatewayv2_route" "clean_house_route_testing" {
  api_id             = aws_apigatewayv2_api.clean_record.id
  route_key          = "GET /record/{actionID}"
  authorization_type = "CUSTOM"
  authorizer_id      = aws_apigatewayv2_authorizer.clean_house_auth.id
  operation_name     = "Recordtest"
  target             = "integrations/${aws_apigatewayv2_integration.clean_house_integration.id}"
}

resource "aws_apigatewayv2_integration" "clean_house_integration" {
  api_id           = aws_apigatewayv2_api.clean_record.id
  integration_type = "AWS_PROXY"

  description            = "clean_house recorder integration"
  integration_uri        = aws_lambda_function.homeclean_recorder_lambda.invoke_arn
  payload_format_version = "2.0"
}

resource "aws_apigatewayv2_stage" "clean_house_prod_stage" {
  api_id        = aws_apigatewayv2_api.clean_record.id
  name          = "clean_house_prod"
  deployment_id = aws_apigatewayv2_deployment.clean_house_deployment.id

  tags = { project = "clean_house" }
}

resource "aws_apigatewayv2_deployment" "clean_house_deployment" {
  api_id      = aws_apigatewayv2_api.clean_record.id
  description = "clean house prod deployment"

  lifecycle {
    create_before_destroy = true
  }

  depends_on = [aws_apigatewayv2_route.clean_house_route]
}

# 適当なので全部のroleをこれにしている。本当はlambdaのRoleとgatewayのlambda呼び出しロールは分けたほうが安全だろうが、toy projectなので。
resource "aws_iam_role" "homeclean_lambda_role" {
  name                = "homeclean_lambda_role"
  managed_policy_arns = [
    "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole",
    "arn:aws:iam::399923773482:policy/AllowDynamoDBAccess"
  ]
  assume_role_policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": ["lambda.amazonaws.com", "apigateway.amazonaws.com"]
      },
      "Effect": "Allow",
      "Sid": ""
    }
  ]
}
EOF

  tags = {
    project = "clean_house"
  }
}

resource "aws_iam_role_policy" "clean_home_api_invocation" {
  name = "default"
  role = aws_iam_role.homeclean_lambda_role.id

  policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Action": "lambda:InvokeFunction",
      "Effect": "Allow",
      "Resource": ["${aws_lambda_function.homeclean_recorder_lambda.arn}", "${aws_lambda_function.homeclean_auth_lambda.arn}"]
    }
  ]
}
EOF
}

resource "aws_lambda_function" "homeclean_recorder_lambda" {
  function_name = "clean_house_recorder"
  role          = aws_iam_role.homeclean_lambda_role.arn
  runtime       = "provided.al2"
  architectures = ["arm64"]
  handler       = "main"
  # Configured in initial tf
  s3_bucket     = "clean-house-lambdas"
  s3_key        = "recorder.zip"

  environment {
    variables = {
      version = "1"
    }
  }

  tags = {
    project = "clean_house"
  }
}

resource "aws_lambda_function" "homeclean_auth_lambda" {
  function_name = "clean_house_apiauth"
  role          = aws_iam_role.homeclean_lambda_role.arn
  runtime       = "provided.al2"
  # コスト低いらしいので
  architectures = ["arm64"]
  handler       = "main"

  # Configured in initial tf
  s3_bucket = "clean-house-lambdas"
  s3_key    = "apiauth.zip"

  environment {
    variables = {
      version = "1"
    }
  }

  tags = {
    project = "clean_house"
  }
}

resource "aws_apigatewayv2_authorizer" "clean_house_auth" {
  api_id                            = aws_apigatewayv2_api.clean_record.id
  authorizer_type                   = "REQUEST"
  authorizer_uri                    = aws_lambda_function.homeclean_auth_lambda.invoke_arn
  # https://docs.aws.amazon.com/apigateway/latest/developerguide/http-api-lambda-authorizer.html
  identity_sources                  = ["$request.querystring.token", "$context.requestTimeEpoch"]
  name                              = "homeclean-authorizer"
  authorizer_payload_format_version = "2.0"
  enable_simple_responses           = true

}

resource "aws_dynamodb_table" "clean_house_db" {
  name         = "clean_houseDB"
  billing_mode = "PAY_PER_REQUEST"

  attribute {
    name = "action"
    type = "S"
  }
  hash_key = "action"

  tags = {
    project = "clean_house"
  }

  # たぶんいらないが一応
  lifecycle { ignore_changes = [read_capacity, write_capacity] }
}