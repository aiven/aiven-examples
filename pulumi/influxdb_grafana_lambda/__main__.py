import pulumi
import pulumi_aiven as aiven
import pulumi_aws as aws


# Print out connection info
def export_details(avn, service_type):
    pulumi.export(service_type + "_uri", avn.service_uri)
    pulumi.export(service_type + "_username", avn.service_username)
    pulumi.export(service_type + "_password", avn.service_password)
    pulumi.export(service_type + "_state", avn.state)


# Create service in Aiven
def create_service(service_name, plan, service_type):
    avn = aiven.Service(service_name,
                        project=avn_project,
                        cloud_name=cloud_region,
                        service_name=service_name,
                        plan=plan,
                        service_type=service_type,
                        )
    export_details(avn, service_type)
    return avn


# Create integration between services
def create_integration(name, integration_type, src_service, dest_service):
    aiven.ServiceIntegration(name,
                             project=avn_project,
                             destination_service_name=src_service.service_name,
                             source_service_name=dest_service.service_name,
                             integration_type=integration_type
                             )


# Lambda function
def create_lambda(depends_on_resource):
    # Create Lambda IAM lambda_role
    lambda_role = aws.iam.Role('lambdaRole',
                               assume_role_policy="""{
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "sts:AssumeRole",
                    "Principal": {"Service": "lambda.amazonaws.com"},
                    "Effect": "Allow",
                    "Sid": ""
                }
            ]
        }"""
                               )

    lambda_layer = aws.lambda_.LayerVersion("lambdaLayer",
                                            compatible_runtimes=["python3.8"],
                                            code=pulumi.FileArchive("lambda_layer"),
                                            layer_name="lambda_layer_name")

    func = aws.lambda_.Function(
        resource_name='ServerlessFunction',
        role=lambda_role.arn,
        runtime="python3.8",
        handler="lambda_code.lambda_handler",
        environment={"variables": {"SERVICE_URI": depends_on_resource.service_uri}},
        code=pulumi.AssetArchive({'.': pulumi.FileArchive('lambda_func')}),
        opts=pulumi.ResourceOptions(depends_on=[depends_on_resource]),
        layers=[lambda_layer.arn],
    )

    pulumi.export('lambda_name', func.name)
    return func


def create_lambda_trigger(func):
    trigger_rule = aws.cloudwatch.EventRule("lambdaEventRule",
                                            schedule_expression="rate(1 minute)")

    aws.lambda_.Permission("allowCloudwatch",
                           action="lambda:InvokeFunction",
                           function=func.name,
                           principal="events.amazonaws.com",
                           source_arn=trigger_rule.arn)

    event_target = aws.cloudwatch.EventTarget("lambdaEventTarget",
                                              arn=func.arn,
                                              rule=trigger_rule.name
                                              )

    pulumi.export('trigger_rule', trigger_rule.name)
    pulumi.export('event_target', event_target.arn)


conf = pulumi.Config()
avn_project = conf.require('aiven_project')
cloud_region = conf.require('aiven_cloud_region')

grafana = create_service("pulumi-grafana", "startup-4", "grafana")
influxdb = create_service("influxdb-grafana", "startup-4", "influxdb")
create_integration("pulumi-grafana-influxdb", "dashboard", influxdb, grafana)

lambda_func = create_lambda(influxdb)
create_lambda_trigger(lambda_func)
