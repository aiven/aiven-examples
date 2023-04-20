## This folder contains examples used for OpenSearch course made by Aiven

### Data discovery with Kafka topic containing measurements values

To demonstrate data discovery based on measurements data

1. Create an OpenSearch cluster
2. Create an Apache Kafka cluster
3. Add a topic "measurements" to Kafka
4. Copy kcat.config.example, remove ".example" and set your Kafka connection details
5. Run the script measurements_generator.sh to add data to the topic
6. Create a Kafka OpenSearch connector and replciate the data to OpenSearch

Above steps can be done with setting project and services names in `lab.env` and run
```
./lab.sh up
```

To teardown these services and cleanup
```
./lab.sh down
```

### Term level and full-text search query examples

Below you can find the examples that are provided in the training to show term-level and full-text search requests.
You can copy the content and past it in OpenSearch Dashboards Dev Tools, you can do it example by example. Or, alternatively, bring all examples together and then select the one you want to run from the DevTools.

Create an index with predefined explicit mapping:
```bash
PUT /buildings
{
  "mappings": {
    "properties": {
      "id": {
        "type": "keyword"
      },
      "location": {
        "properties": {
          "coordinates": {
            "type": "geo_point"
          },
          "address": {
            "type": "text"
          }
        }
      },
      "built_year": {
        "type": "integer"
      },
      "in_use": {
        "type": "boolean"
      },
      "description": {
        "type": "text"
      }
    }
  }
}
```

Add an item to the index according to the schema:
```bash
PUT buildings/_doc/1
{
 "id": "44",
 "location": {
   "coordinates": {
     "lat": 40.7128,
     "lon": -74.0060
   },
   "address": "789 Wall Street, New York, NY 10005, USA"
 },
 "built_year": 2008,
 "in_use": true,
 "description": "This modern office building, constructed in 2008, features advanced building management systems designed for efficient operations and maintenance. It includes a HVAC system with zoned controls for personalized comfort and energy savings, and a smart lighting system with motion sensors for optimal energy usage."
}
```

Term search example by value:
```bash
GET buildings/_search
{
 "query": {
   "term": {
     "id": "44"
   }
 }
}
```

Term search example by prefix:
```bash
GET buildings/_search
{
 "query": {
   "prefix": {
     "location.address": "789"
   }
 }
}
```

Term search example using a range of values:
```bash
GET buildings/_search
{
 "query": {
   "range": {
     "built_year": {
       "gte": 1998,
       "lte": 2009
     }
   }
 }
}
```

Full-text search:
```bash
GET buildings/_search
{
 "query": {
   "match": {
     "description": "secure with zone control"
   }
 }
}
```

Full-text search with a slop:
```bash
GET buildings/_search
{
 "query": {
   "match_phrase": {
     "description": {
       "query": "smart motion sensors",
        "slop": 5
     }
   }
 }
}
```



