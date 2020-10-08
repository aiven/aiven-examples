## Analyzing Reddit Comments using Aiven for Elasticsearch

```secrets#production
client_id=
client_secret=
reddit_username=
reddit_password=
```

This document is a [`rundoc`](https://github.com/eclecticiq/rundoc), this means you can save it locally to your machine and run it with the command: `rundoc run Runbook.md`. See the link for info about installing or running select blocks of code.

### What?

We will be building a small app to analyze Reddit comments using Elasticsearch, Kakfa and Kafka Connect; graciously hosted by [Aiven](https://aiven.io). We will be doing this in one of 2 ways: using the Reddit dump of all public comments from May 2015 (more on this later) and using the Reddit API for real time updates.

### How?

We will be using the following:

1. An Aiven Account
2. Terraform
3. Elasticearch (and Kibana)
4. Golang (graw and go-kafka modules)
5. A Kaggle account (for Scenario 1)
6. A Reddit account (for Scenario 2)


### Initial Setup

First, we need to create the services we want to use in [Aiven](https://aiven.io).
We can do this with Terraform. If Terraform is new (or _newish_) to you, then you can get acquainted with our [blog post](https://aiven.io/blog/aiven-terraform-provider-v2-release) 

Then, we will be creating the following services:

- Kafka: for ingesting comments from Reddit
- Elasticsearch: for storing Reddit comments and searching with Kibana
- InfluxDB: for Metrics for both of the above services (*Optional*)
- Grafana: for dashboards of the above metrics (*Optional*)

You will need to go to your profile in the [Aiven Console](https://console.aiven/io) and generate an API key for Terraform to use, then save it in `deploy/secrets.tfvars`.

```bash
cd deploy
terraform init
terraform apply # you can run `plan` first if you like
```

While we wait for these services to come up, you can get started on one (or both) of the scenarios below!

### Scenario 1: May 2015 Comments

Want to analyse 20GB of Redditors views from 5 years ago? You are in luck! Now you can see how politically (in)correct the populous of Reddit was in 2015 by downloading a subset of their **massive** release through [Kaggle](https://www.kaggle.com/reddit/reddit-comments-may-2015).

The download comes zipped as a `SQLite` database and we have done the hard work by writing some code to push this to your freshly deployed Elasticsaearch cluster. I know, pretty nice, right? Note that this means you cannot comment on the quality of the code (of course you can, but maybe you can [improve it as well](https://github.com/aiven/aiven-examples/pulls)?)

```bash
cd 2015-reddit
go run main.go
```

Sit back and wait for the comments to come rolling in...you might wait a while so check out Reddit, maybe?


### Scenario 2: Real Time Reddit

First, we need to create a Reddit app (a `script`) by going to the [Apps](https://www.reddit.com/prefs/apps) page in your Reddit account settings. Save the Client ID and Secret here (along with your reddit credentials):


We will use them to create an `agent` file for our Reddit app to authenticate with:

```bash
cat  > ./real-time-reddit/.env<< EOF
UA="Unix:${client_id}:v0.0.1 (by /u/${reddit_username})"
APP_ID="$client_id"
APP_SECRET="$client_secret"
REDDIT_USERNAME="${reddit_username}"
REDDIT_PASSWORD="${reddit_password}"
EOF
```

You can edit the `main.go` file to change the subreddit that the comments are pulled from, or you can leave it as `/r/candycrush` by default (we all have our weaknesses). You will also need to provide the credentials for your Kafka service in the `real-time-reddit` folder (the `ca.pem` you download from the [Aiven Web Console](https://console.aiven.io)).

```bash
go run ./real-time-reddit/main.go
```

### Kibana Queries

We have data! Now, we want to analyse it. What's that? 

> You need an index first!

No no, our friendly Terraform script did this for us! We have a simple `reddit*` index that will handle comments from either scenario you followed. All you need to do is head over to the [Aiven Web Console](https://console.aiven.io) and click on your `Elasticsearch service`, select the `Kibana` tab and make a note of the password. Click the link and enter your credentials.

Kibana will now think you are an absolute noob because it cannot see any data but feel free to throw any gestures you like at it when you click `Connect your Elasticsearch Index`. We will create an Index pattern for `reddit*` and Kibana will do the rest for you (make sure you have a time field working!).

Let's click over to `Visualize` and create a new visualization. This is where the time field is crucial. If you followed **Scenario 1** then you have data from 5 years ago and the overall count you see right now is...nada, zip, null, nothing. So we need to change the time range next to the search field and select **6 years ago to now**.
Now you should see that you have a few hundred thousand comments and we are ready to get going!

