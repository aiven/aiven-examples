from faker.providers import BaseProvider
import random
import time

StockSymbols = [
    "AVN", "KAFKA", "PSQL", "MYSQL", "OS", "CQL", "REDIS", "INFLUX", "GRAFANA",
    "M3"
]
StockCurrentValues = [
    999.99, 888.88, 777.77, 666.66, 20.1, 20.2, 12.1, 25.1, 25.1, 27.5
]
StockUpProb = [0.5, 0.6, 0.7, 0.8, 0.9, 0.19, 0.4, 0.3, 0.2, 0.1]
ShuffleProb = 0.2
ChangeAmount = 1.68


class StockProvider(BaseProvider):
    def stock_symbol(self):
        return random.choice(StockSymbols)

    def stock_value(self, symbol):
        indexStock = StockSymbols.index(symbol)
        currentval = StockCurrentValues[indexStock]
        goesup = 1
        if random.random() > StockUpProb[indexStock]:
            goesup = -1
        nextval = round(currentval + random.random() * ChangeAmount * goesup,
                        2)
        StockCurrentValues[indexStock] = nextval

        return nextval

    def reshuffle_probs(self, symbol):
        indexStock = StockSymbols.index(symbol)
        StockUpProb[indexStock] = random.random()

    def produce_msg(self):
        stock_symbol = self.stock_symbol()
        ts = time.time()
        if random.random() > ShuffleProb:
            self.reshuffle_probs(stock_symbol)
        message = {
            "symbol": stock_symbol,
            "bid_price": self.stock_value(stock_symbol),
            "ask_price": self.stock_value(stock_symbol),
            "time_stamp": int(ts * 1000)
        }
        key = {"symbol": stock_symbol}
        return message, key