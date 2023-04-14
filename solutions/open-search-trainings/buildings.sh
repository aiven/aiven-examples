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


GET buildings/_search
{
 "query": {
   "term": {
     "id": "44"
   }
 }
}

GET buildings/_search
{
 "query": {
   "prefix": {
     "location.address": "789"
   }
 }
}

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

GET buildings/_search
{
 "query": {
   "match": {
     "description": "secure with zone control"
   }
 }
}


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


