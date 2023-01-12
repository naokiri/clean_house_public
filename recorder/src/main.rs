use aws_sdk_dynamodb::Client;
use aws_sdk_dynamodb::model::{AttributeValue, ReturnConsumedCapacity, ReturnValue};
use chrono::Utc;
use lambda_http::{service_fn, Error, Body};
use lambda_http::aws_lambda_events::apigw::{ApiGatewayV2httpRequest, ApiGatewayV2httpResponse};
use lambda_http::http::{HeaderMap, StatusCode};
use lambda_runtime::LambdaEvent;
use serde_json::{json};
use log;
use env_logger;

// authを通ってvalidなリクエストなのでコマンド内容に応じて最終日時を保存する
#[tokio::main]
async fn main() -> Result<(), Error> {
    env_logger::init();
    let config = aws_config::load_from_env().await;
    //log::error!("{:?}", config.region());
    let client = Client::new(&config);

    let func = service_fn(|event| func(&client, event));
    lambda_runtime::run(func).await
}

async fn func(dynamodb_client: &Client, event: LambdaEvent<ApiGatewayV2httpRequest>) -> Result<ApiGatewayV2httpResponse, Error> {
    let fallback = "undefined".to_string();
    let action = event.payload.path_parameters.get("actionID").unwrap_or(&fallback);
    let time = Utc::now().to_rfc3339();
    // Table names and keys defined in terraform
    let _result = dynamodb_client.put_item()
        .table_name("clean_houseDB")
        .item("action", AttributeValue::S(action.to_string()))
        .item("time", AttributeValue::S(time.to_owned()))
        .return_values(ReturnValue::AllOld)
        .return_consumed_capacity(ReturnConsumedCapacity::Total)
        .send().await.expect("なんか失敗");

    // log::error!("{:?}", result);

    let mut header = HeaderMap::new();
    header.insert("content-type", "application/json".parse().unwrap());
    Ok(ApiGatewayV2httpResponse {
        status_code: i64::from(StatusCode::OK.as_u16()),
        headers: header,
        multi_value_headers: Default::default(),
        body: Some(Body::Text(json!({
            "status": "success",
            "action": action,
            "time": time,
          }).to_string())),
        is_base64_encoded: Some(false),
        cookies: vec![],
    })
}