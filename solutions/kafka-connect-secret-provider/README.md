# Kafka Connect Secret Provider

This demo uses the Secret Provider for Aiven Kafka Connect in order to resolve a database secret from AWS Secret Manager.

## Requirement

- `avn`
- `jq`
- `psql`
- `terraform`

## Usage

- Update `aiven_project` in `variables.tf` to your project name.

- Create a secret in AWS Secret Manager with name `aiven/test` and key `password` (you can also change this in `variables.tf`).

- Provide an IAM User with key pair and permissions to read the secret:
```json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue",
                "secretsmanager:DescribeSecret",
                "secretsmanager:GetResourcePolicy"
            ],
            "Resource": "arn:aws:secretsmanager:eu-central-1:XXXXXXXXXX:secret:test/aiven-XXXX"
        }
    ]
}
```

- Set environment variables `AWS_ACCESS_KEY` and `AWS_SECRET_ACCESS_KEY`

```bash
export AWS_ACCESS_KEY=<access-key>
export AWS_SECRET_ACCESS_KEY=<secret-access-key>
```

- Then run:
```bash
terraform init
terraform apply
```

- After this you can create samples in the database and check the topic with:
```bash
./insert_samples.sh
./read_topic.sh
```

- This should output something like this:
```json
[
  {
    "before": null,
    "after": {
      "id": 1,
      "name": "7PbDBxPo9n",
      "value": 33
    },
    "source": {
      "version": "2.5.0.Final",
      "connector": "postgresql",
      "name": "topic",
      "ts_ms": 1720103847351,
      "snapshot": "false",
      "db": "defaultdb",
      "sequence": "[null,\"151130776\"]",
      "schema": "public",
      "table": "test",
      "txId": 851,
      "lsn": 151130776,
      "xmin": null
    },
    "op": "c",
    "ts_ms": 1720103848230,
    "transaction": null
  },
  {
    "before": null,
    "after": {
      "id": 2,
      "name": "Tz1iU12uKD",
      "value": 95
    },
    "source": {
      "version": "2.5.0.Final",
      "connector": "postgresql",
      "name": "topic",
      "ts_ms": 1720103847351,
      "snapshot": "false",
      "db": "defaultdb",
      "sequence": "[null,\"151131016\"]",
      "schema": "public",
      "table": "test",
      "txId": 851,
      "lsn": 151131016,
      "xmin": null
    },
    ...
```

- Clean up:
```bash
terraform destroy
```

- And unset environment variables:
```bash
unset AWS_ACCESS_KEY
unset AWS_SECRET_ACCESS_KEY
```
