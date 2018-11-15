from psycopg2.extras import RealDictCursor
import psycopg2

uri = "postgres://avnadmin:nr0dfnswz36xs9pi@pg-3b8d4ed6-myfirstcloudhub.aivencloud.com:20985/defaultdb?sslmode=require"

db_conn = psycopg2.connect(uri)
c = db_conn.cursor(cursor_factory=RealDictCursor)

c.execute("SELECT 1 = 1")
result = c.fetchone()
print(result)
