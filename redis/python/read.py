# Copyright (c) 2018 Aiven, Helsinki, Finland. https://aiven.io/
import redis

client = redis.StrictRedis(
    host='redis-3b8d4ed6-myfirstcloudhub.aivencloud.com',
    port=15194,
    password='<your password here>',
    ssl=True,
    ssl_ca_certs='/etc/pki/tls/certs/ca-bundle.crt'
)

client.ping()
value = client.get('foo')
print(value)
