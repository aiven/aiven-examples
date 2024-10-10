# Kafka Custom Metrics Dashboard

# Aiven to Grafana Integration Guide

This guide explains how to enable metrics integration for Aiven Kakfa and how to import the custom metrics dashboard. By following these steps, you’ll be able to monitor and visualize custom metrics for your Aiven Kafka service in Grafana. 

## Prerequisites

- An [Aiven for Apache Kafka](https://aiven.io/docs/products/kafka) service
- An [Aiven for Metrics](https://aiven.io/docs/products/metrics) (Thanos) service
- An [Aiven for Grafana](https://aiven.io/docs/products/grafana) service

## Step 1: Enable Metrics Integration for Aiven Kafka

1. **Log in to the Aiven Console** at [console.aiven.io](https://console.aiven.io/).
2. **Navigate to Your Kafka Service**: Select the specific Kafka service you want to monitor.
3. **Enable Metrics Integration**:
    - Go to the **Metrics** tab.
    - Click the **Enable metrics integration** button. When prompted for where to send metrics, select your "Aiven for Metrics" (Thanos) service and click the **Enable** button. This will allow your Kafka service to start sending metrics to the Thanos service.

## Step 2: Enable Thanos Integration with Aiven Grafana

1. Go to your Thanos service in the Aiven Console and click the **Integrations** tab.
2. Select your Grafana service and click **Enable**. This will enable your Thanos service to start sending metrics to the Aiven Grafana service.


## Step 3: Import the Custom Kafka dashboard in Aiven Grafana
1. Download the [Kafka-Custom-Metrics-Dashboard.json](Kafka-Custom-Metrics-Dashboard.json) dashboard file. 
2. Log in to your Aiven Grafana web UI and go to **Dashboards**. 
3. Click **New** and select **Import**.
4. In the **Import dashboard** page, select the dashboard json that you saved previously and click **Load**.
5. In the dashboard options, change any settings that you'd like and select your Aiven Thanos service for the **aiven-thanos-metrics-store** data source field. Click **Import** once done. This will import and open the new custom Kafka dashboard. 
