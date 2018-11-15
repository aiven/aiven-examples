# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
import redis

client = redis.StrictRedis(
    host='redis-3b8d4ed6-myfirstcloudhub.aivencloud.com',
    port=15194,
    password='nr0dfnswz36xs9pi',
    ssl=True,
    ssl_ca_certs='/etc/pki/tls/certs/ca-bundle.crt'
)

client.ping()
value = client.get('foo')
print(value)
