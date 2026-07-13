# Side-by-side: DB2 response vs PostgreSQL response

Same API call (`GET /portfolio/Alice`), same app image — left: DB2-backed, right: Postgres-backed.

```
{						  {
    "accountID": "ACCT-1001",			      "accountID": "ACCT-1001",
    "lastTrade": 0.0,				      "lastTrade": 0.0,
    "owner": "Alice",				      "owner": "Alice",
    "stocks": {					      "stocks": {
	"AAPL": {				  	  "AAPL": {
	    "commission": 9.99,			  	      "commission": 9.99,
	    "date": "2026-07-10",		  	      "date": "2026-07-10",
	    "price": 210.25,			  	      "price": 210.25,
	    "shares": 200,			  	      "shares": 200,
	    "symbol": "AAPL",			  	      "symbol": "AAPL",
	    "total": 42050.0			  	      "total": 42050.0
	},					  	  },
	"IBM": {				  	  "IBM": {
	    "commission": 9.99,			  	      "commission": 9.99,
	    "date": "2026-07-10",		  	      "date": "2026-07-10",
	    "price": 245.5,			  	      "price": 245.5,
	    "shares": 100,			  	      "shares": 100,
	    "symbol": "IBM",			  	      "symbol": "IBM",
	    "total": 24550.0			  	      "total": 24550.0
	},					  	  },
	"MSFT": {				  	  "MSFT": {
	    "commission": 9.99,			  	      "commission": 9.99,
	    "date": "2026-07-10",		  	      "date": "2026-07-10",
	    "price": 487.0,			  	      "price": 487.0,
	    "shares": 120,			  	      "shares": 120,
	    "symbol": "MSFT",			  	      "symbol": "MSFT",
	    "total": 58440.0			  	      "total": 58440.0
	}					  	  }
    },						      },
    "total": 125040.0				      "total": 125040.0
}						  }
```

## Full-workload diff (18 responses)

```
$ diff -r baseline-db2/ postgres/
(no output — byte-for-byte identical)
```
