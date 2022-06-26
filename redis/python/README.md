### Redis® Python Example

This example uses the [redis](https://pypi.org/project/redis/) library to connect to Redis®, write a key/value pair, and read it out again.

#### Installing Dependencies  

```
pip install redis
```

#### Running The Example
Note: You can retrieve the connection details from the Aiven Console overview tab.
```
./main.py --host <redis host> --password <redis password> --port <redis port>
```