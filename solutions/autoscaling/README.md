# autoscale

This is a demo of using avn CLI and prometheus endpoint to upsize an Aiven service when system resource reaches a defined threshold.  This demo would take around 10 - 15 minutes to be completed.

### *This is NOT for production use, safe guards should be placed for any automation on changing service plans.*

## Requirement

- `avn` 
- `curl`
- `jq`
- `psql`

## Steps

- Update the following values in `autoscale.env`

| Tables                 | Description                 |
| ---------------------- |:---------------------------:|
| PROJECT                | project name                |
| SERVICE                | service name                |
| AUTOSCALE_THRESHOLD    | threshold to upsize         |  
| AUTOSCALE_INTERVAL     | monito interval in seconds  |
| AUTOSCALE_PLAN_TYPE    | service type                |
| AUTOSCALE_CURRENT_PLAN | plan size to start with     |
| AUTOSCALE_NEXT_PLAN    | plan size to upgrade to     |
| CPU_IDLE_MAX           | percentage of cpu idle      |
| PROMETHEUS_NAME        | promeheus endpoint name     |
| PROMETHEUS_USER        | promeheus endpoint user     |
| PROMETHEUS_PASS        | promeheus endpoint password |


- Run `./autoscale.sh setup`, this would create the service and the prometheus integration endpoint that are needed for this demo.  It takes around 3 minutes to create a new service.
```
./autoscale.sh setup
```

- Run `./autoscale.sh demo`, this starts to check cpu idle percentage every 10 seconds, when it is less than `60%` which means overall cpu usage is over `40%` it will keep track of the duration, if this continues for 60 seconds, it will trigger `avn` CLI to upsize the plan to `startup-8`.  This process does not exit until `CTRL + C`, *please keep this process and terminal running through out the entire demo.*
```
./autoscale.sh demo
```

- This step runs an expensive PostgreSQL query to spike up CPU load that may take a few minutes to complete, it is expected that you will not get the sum response in over 1 minute.  Go to Aiven Console and open the service `Metrics` view to monitor the change in CPU usage, click on the `Nodes` icon to see node replacement during the plan upgrade, it is expected in `./autoscale.sh demo` terminal you will get `Unable to get metrics...` during the new node takes over.  Open a new terminal to monitor spike in CPU load when running the below command.
```
./autoscale.sh pgload
```

- Run `./autoscale.sh teardown` to delete all the resources created from this demo.
```
./autoscale.sh teardown
```

## Example Demo

#### Running `./autoscale.sh setup`
```
INFO	Service 'autoscale-demo' state is now 'REBUILDING'
INFO	Waiting for services to start
INFO	Waiting for services to start
INFO	Waiting for services to start
INFO	Waiting for services to start
INFO	Service 'autoscale-demo' state is now 'RUNNING'
INFO	Service(s) RUNNING: autoscale-demo
autoscale-demo environment is ready! run [./autoscale.sh demo] to start the demo.
```

#### Running `./autoscale.sh demo`
```
time ./autoscale.sh demo
Prometheus URL: https://********:********@**************.aivencloud.com:9273/metrics
Waiting for metrics to be available....CPU idle 96.64608710161848%
CPU idle 96.64608710161848%
CPU idle 96.68056713928263%
CPU idle 45.32554257095156%
CPU usage reached threshold! [1]
CPU idle 45.32554257095156%
CPU usage reached threshold! [2]
CPU idle 45.32554257095156%
CPU usage reached threshold! [3]
CPU idle 35.76214405360142%
CPU usage reached threshold! [4]
CPU idle 35.76214405360142%
CPU usage reached threshold! [5]
CPU idle 35.76214405360142%
CPU usage reached threshold! [6]
Upgrading this plan!
INFO	Service 'autoscale-demo' state is now 'REBALANCING'
INFO	Waiting for services to start
INFO	Waiting for services to start
INFO	Waiting for services to start
INFO	Waiting for services to start
INFO	Service 'autoscale-demo' state is now 'RUNNING'
INFO	Service(s) RUNNING: autoscale-demo
Unable to get metrics...
Unable to get metrics...
Unable to get metrics...
Unable to get metrics...
Unable to get metrics...
Unable to get metrics...
CPU idle 96.14485981308403%
```

#### Running `./autoscale.sh pgload`
```
time ./autoscale.sh pgload
Running an expensive query...
SELECT SUM(val)
FROM (
    SELECT SIN(RADIANS(number)) + COS(RADIANS(number)) AS val
    FROM generate_series(1, 300000000) AS number
) AS subquery;        sum
--------------------
 135.24284129470215
(1 row)
```

#### Running `./autoscale.sh teardown`
```
./autoscale.sh teardown
Deleted autoscale-prometheus ID: b9c562ee-37f2-4ed7-a17b-e8a83d491d33
***********************************************************************
Please re-enter the service name(s) to confirm the service termination.
This cannot be undone and all the data in the service will be lost!
Re-entering service name(s) can be skipped with the --force option.
***********************************************************************
Re-enter service name 'autoscale-demo' for immediate termination: INFO	autoscale-demo: terminated
```
