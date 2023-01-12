set -xn

tmp_dir=$(mktemp -d -t tmpXXXXXXX)
cp target/lambda/api_auth/bootstrap ${tmp_dir}
docker run -it --rm -v ${tmp_dir}:/var/task:ro,delegated -e DOCKER_LAMBDA_USE_STDIN=1 -e AWS_LAMBDA_FUNCTION_MEMORY_SIZE=128 -e RUST_LOG=info lambci/lambda:provided main
rm -r ${tmp_dir}