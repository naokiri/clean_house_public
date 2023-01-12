use aws_lambda_events::apigw::{ApiGatewayCustomAuthorizerPolicy, IamPolicyStatement, ApiGatewayV2CustomAuthorizerV2Request, ApiGatewayV2CustomAuthorizerSimpleResponse};
use aws_lambda_events::chrono::{FixedOffset, NaiveDateTime, Timelike, TimeZone};
use lambda_runtime::{run, service_fn, Error, LambdaEvent};
use serde_json::json;
use sha2::{Sha256, Digest};
use sha2::digest::FixedOutput;

///
/// API Gateway auth
///
///
#[tokio::main]
async fn main() -> Result<(), Error> {
    env_logger::init();
    run(service_fn(function_handler)).await
}

pub async fn function_handler(event: LambdaEvent<ApiGatewayV2CustomAuthorizerV2Request>) -> Result<ApiGatewayV2CustomAuthorizerSimpleResponse, Error> {
    // passed parameter defined in aws_apigatewayv2_authorizer in terraform
    if let Some(token) = event.payload.query_string_parameters.get("token") {
        // do something
        if let Some(datetime) = NaiveDateTime::from_timestamp_millis(event.payload.request_context.time_epoch) {
            let jptz = FixedOffset::east_opt(9 * 60 * 60).unwrap();
            let jptime = jptz.from_utc_datetime(&datetime);
            let jphour = jptime.with_minute(0).unwrap().with_second(0).unwrap().with_nanosecond(0).unwrap();
            let hourstring = jphour.to_rfc3339();
            if sha256hash_hexstring(&hourstring).eq(token) {
                return Ok(custom_authorizer_response(
                    true,
                    &hourstring));
            }
        }
    }

    Ok(custom_authorizer_response(
        false,
        ""))
}

pub fn custom_authorizer_response(is_authorized: bool, msg: &str) -> ApiGatewayV2CustomAuthorizerSimpleResponse {
    ApiGatewayV2CustomAuthorizerSimpleResponse {
        is_authorized,
        context: json!({ "msg": msg }),
    }
}

pub fn sha256hash_hexstring(data: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(data);
    let result = hasher.finalize();
    hex::encode(&result[..])
}

#[cfg(test)]
mod test {
    use crate::{function_handler, sha256hash_hexstring};

    #[test]
    fn sha256hash() {
        let result = sha256hash_hexstring("foo");
        // Assuming google search result "sha256 foo" is correct.
        assert_eq!(result, "2c26b46b68ffc68ff99b453c1d30413413422d706483bfa0f98a5e886266e7ae");
    }

    #[tokio::test]
    async fn test_my_lambda_handler() {
        let _ = env_logger::builder().is_test(true).try_init();

        let input = serde_json::from_str(include_str!("unittest_resource/input.json")).expect("failed to parse event");
        let context = lambda_runtime::Context::default();

        let event = lambda_runtime::LambdaEvent::new(input, context);
        let response = function_handler(event).await.expect("failed to handle request");
    }
}
