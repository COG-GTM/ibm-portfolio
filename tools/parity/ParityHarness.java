/*
       Copyright 2023-2024 Kyndryl, All Rights Reserved

   Licensed under the Apache License, Version 2.0 (the "License");
   you may not use this file except in compliance with the License.
   You may obtain a copy of the License at

       http://www.apache.org/licenses/LICENSE-2.0

   Unless required by applicable law or agreed to in writing, software
   distributed under the License is distributed on an "AS IS" BASIS,
   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
   See the License for the specific language governing permissions and
   limitations under the License.
 */

package com.ibm.hybrid.cloud.sample.stocktrader.portfolio.parity;

import com.ibm.hybrid.cloud.sample.stocktrader.portfolio.rules.CommissionRules;
import com.ibm.hybrid.cloud.sample.stocktrader.portfolio.rules.LoyaltyRules;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.InetSocketAddress;
import java.nio.charset.StandardCharsets;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.sql.CallableStatement;
import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Types;
import java.util.ArrayList;
import java.util.Collection;
import java.util.LinkedHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;
import java.util.TreeSet;

/** Side-by-side parity harness for the DB2 -> PostgreSQL migration of the portfolio service.
 *
 *  It drives the same application scenario (create portfolio -> buy across loyalty tiers ->
 *  fetch portfolio/returns -> sell -> delete) against both engines, over identical SQL, with
 *  one deliberate difference:
 *
 *    - DB2      calls the legacy UPDATE_LOYALTY_LEVEL / CALCULATE_COMMISSION stored procedures.
 *    - Postgres calls the lifted LoyaltyRules / CommissionRules classes that the service now uses.
 *
 *  Every step's response is compared field by field, and the final table contents are
 *  reconciled row by row.  A tamper endpoint provides the negative control.
 */
public class ParityHarness {
	private static final String OWNER   = "PARITY_TRADER";   //survives the scenario, so it can be reconciled
	private static final String SCRATCH = "PARITY_SCRATCH";  //deleted by the scenario, to prove the FK cascade
	private static final String QUOTE_DATE = "2026-02-01";   //fixed so both engines see identical quotes
	private static final double TOLERANCE = 0.000001;

	private final Backend db2;
	private final Backend postgres;

	ParityHarness(Backend db2, Backend postgres) {
		this.db2 = db2;
		this.postgres = postgres;
	}

	public static void main(String[] args) throws Exception {
		int port = Integer.parseInt(System.getProperty("parity.port", "8099"));

		Backend db2 = new Backend("DB2", "IBM DB2 11.5 (stored procedures)", true,
			System.getProperty("db2.url", "jdbc:db2://localhost:50000/trader"),
			System.getProperty("db2.user", "db2inst1"),
			System.getProperty("db2.password", "db2inst1"));

		Backend postgres = new Backend("PostgreSQL", "PostgreSQL 16 (logic in Java service layer)", false,
			System.getProperty("pg.url", "jdbc:postgresql://localhost:5432/trader?sslmode=disable"),
			System.getProperty("pg.user", "trader"),
			System.getProperty("pg.password", "trader"));

		ParityHarness harness = new ParityHarness(db2, postgres);

		HttpServer server = HttpServer.create(new InetSocketAddress(port), 0);
		server.createContext("/", harness::serveDashboard);
		server.createContext("/api/run", exchange -> harness.serveJson(exchange, harness.runScenario()));
		server.createContext("/api/tamper", exchange -> harness.serveJson(exchange, harness.tamperAndReconcile()));
		server.setExecutor(null);
		server.start();

		System.out.println("Parity dashboard: http://localhost:" + port + "/");
	}

	// ----------------------------------------------------------------- scenario

	/** Runs the whole scenario against both engines and returns the comparison report. */
	Map<String, Object> runScenario() {
		Map<String, Object> report = new LinkedHashMap<>();
		List<Object> steps = new ArrayList<>();
		boolean allMatched = true;

		try {
			db2.reset();
			postgres.reset();

			for (Scenario step : scenario()) {
				Map<String, Object> left  = capture(db2, step);
				Map<String, Object> right = capture(postgres, step);

				List<Object> diffs = diff(left, right);
				boolean matched = diffs.isEmpty();
				allMatched &= matched;

				Map<String, Object> row = new LinkedHashMap<>();
				row.put("name", step.name);
				row.put("detail", step.detail);
				row.put("db2", left);
				row.put("postgres", right);
				row.put("match", matched);
				row.put("diffs", diffs);
				steps.add(row);
			}
		} catch (Exception e) {
			report.put("error", String.valueOf(e));
			allMatched = false;
		}

		report.put("steps", steps);
		report.put("reconciliation", reconcile());
		report.put("allStepsMatched", allMatched);
		report.put("db2Backend", db2.description);
		report.put("postgresBackend", postgres.description);
		return report;
	}

	/** The application scenario, expressed once and run against both engines. */
	private List<Scenario> scenario() {
		List<Scenario> steps = new ArrayList<>();

		steps.add(new Scenario("create portfolio", "POST /" + OWNER + " - opens at Basic with a 50.00 cash balance",
			backend -> backend.createPortfolio(OWNER, "ACCT-9001")));

		steps.add(new Scenario("buy 20 IBM @ 250 (Basic tier)", "total -> 5,000: stays Basic, 9.99 commission",
			backend -> backend.trade(OWNER, "IBM", 20, 250.0)));

		steps.add(new Scenario("buy 60 IBM @ 250 (crosses into Bronze)", "total -> 20,000: Bronze earned, still charged the Basic 9.99",
			backend -> backend.trade(OWNER, "IBM", 60, 250.0)));

		steps.add(new Scenario("buy 200 AAPL @ 250 (crosses into Silver)", "total -> 70,000: charged the Bronze 8.99",
			backend -> backend.trade(OWNER, "AAPL", 200, 250.0)));

		steps.add(new Scenario("buy 100 GOOG @ 500 (crosses into Gold)", "total -> 120,000: charged the Silver 7.99",
			backend -> backend.trade(OWNER, "GOOG", 100, 500.0)));

		steps.add(new Scenario("buy 1800 GOOG @ 500 (block trade, crosses into Platinum)",
			"900,000 trade: Gold 6.99 + half a basis point surcharge; total -> 1,020,000 = Platinum",
			backend -> backend.trade(OWNER, "GOOG", 1800, 500.0)));

		steps.add(new Scenario("fetch portfolio / returns", "GET /" + OWNER + " - holdings, loyalty, commissions and net worth",
			backend -> backend.fetchPortfolio(OWNER)));

		steps.add(new Scenario("sell 900 GOOG @ 500 (block trade at Platinum)", "450,000 trade: Platinum 5.99 + surcharge",
			backend -> backend.trade(OWNER, "GOOG", -900, 500.0)));

		steps.add(new Scenario("sell all 80 IBM @ 250", "position closes, so the Stock row is deleted",
			backend -> backend.trade(OWNER, "IBM", -80, 250.0)));

		steps.add(new Scenario("fetch portfolio / returns after selling", "GET /" + OWNER + " - two holdings left",
			backend -> backend.fetchPortfolio(OWNER)));

		steps.add(new Scenario("delete portfolio " + SCRATCH, "DELETE /" + SCRATCH + " - FK cascade must remove its stock rows",
			backend -> backend.deletePortfolio(SCRATCH)));

		return steps;
	}

	private Map<String, Object> capture(Backend backend, Scenario step) {
		try {
			return step.action.apply(backend);
		} catch (Exception e) {
			Map<String, Object> failure = new LinkedHashMap<>();
			failure.put("error", String.valueOf(e));
			return failure;
		}
	}

	// ----------------------------------------------------------- reconciliation

	/** Row-level reconciliation of everything left in both databases. */
	Map<String, Object> reconcile() {
		Map<String, Object> result = new LinkedHashMap<>();
		List<Object> rows = new ArrayList<>();
		boolean matched = true;

		try {
			Map<String, Map<String, Object>> left  = db2.snapshot();
			Map<String, Map<String, Object>> right = postgres.snapshot();

			Set<String> keys = new TreeSet<>();
			keys.addAll(left.keySet());
			keys.addAll(right.keySet());

			for (String key : keys) {
				Map<String, Object> db2Row = left.get(key);
				Map<String, Object> pgRow  = right.get(key);

				List<Object> diffs = new ArrayList<>();
				if (db2Row == null) {
					diffs.add("row missing in DB2");
				} else if (pgRow == null) {
					diffs.add("row missing in PostgreSQL");
				} else {
					diffs = diff(db2Row, pgRow);
				}

				Map<String, Object> row = new LinkedHashMap<>();
				row.put("key", key);
				row.put("db2", db2Row == null ? new LinkedHashMap<String, Object>() : db2Row);
				row.put("postgres", pgRow == null ? new LinkedHashMap<String, Object>() : pgRow);
				row.put("match", diffs.isEmpty());
				row.put("diffs", diffs);
				rows.add(row);
				matched &= diffs.isEmpty();
			}
		} catch (Exception e) {
			result.put("error", String.valueOf(e));
			matched = false;
		}

		result.put("rows", rows);
		result.put("match", matched);
		return result;
	}

	/** Negative control: corrupt one PostgreSQL row and re-reconcile, which must report MISMATCH. */
	Map<String, Object> tamperAndReconcile() {
		Map<String, Object> result = new LinkedHashMap<>();
		String statement = "UPDATE Portfolio SET commissions = commissions + 0.07, loyalty = 'Bronze' WHERE owner = ?";

		try (Connection connection = postgres.connect();
		     PreparedStatement update = connection.prepareStatement(statement)) {
			update.setString(1, OWNER);
			int updated = update.executeUpdate();
			result.put("tampered", updated + " PostgreSQL row(s)");
			result.put("statement", statement.replace("?", "'" + OWNER + "'"));
		} catch (SQLException e) {
			result.put("error", String.valueOf(e));
		}

		result.put("reconciliation", reconcile());
		return result;
	}

	// ------------------------------------------------------------- comparisons

	/** Field-by-field comparison, with a tolerance for the floating point money columns. */
	private List<Object> diff(Map<String, Object> left, Map<String, Object> right) {
		List<Object> diffs = new ArrayList<>();

		Set<String> keys = new LinkedHashSet<>(left.keySet());
		keys.addAll(right.keySet());

		for (String key : keys) {
			Object a = left.get(key);
			Object b = right.get(key);

			if (a instanceof Map && b instanceof Map) {
				@SuppressWarnings("unchecked")
				List<Object> nested = diff((Map<String, Object>) a, (Map<String, Object>) b);
				for (Object nestedDiff : nested) diffs.add(key + "." + nestedDiff);
			} else if (a instanceof Number && b instanceof Number) {
				double difference = Math.abs(((Number) a).doubleValue() - ((Number) b).doubleValue());
				if (difference > TOLERANCE) diffs.add(key + ": DB2=" + a + " vs PostgreSQL=" + b);
			} else if (!String.valueOf(a).equals(String.valueOf(b))) {
				diffs.add(key + ": DB2=" + a + " vs PostgreSQL=" + b);
			}
		}

		return diffs;
	}

	// --------------------------------------------------------------- http glue

	private void serveDashboard(HttpExchange exchange) throws IOException {
		if (!"/".equals(exchange.getRequestURI().getPath())) {
			exchange.sendResponseHeaders(404, -1);
			return;
		}

		Path dashboard = Paths.get(System.getProperty("parity.dashboard", "tools/parity/dashboard.html"));
		byte[] body = Files.readAllBytes(dashboard);
		exchange.getResponseHeaders().add("Content-Type", "text/html; charset=utf-8");
		exchange.sendResponseHeaders(200, body.length);
		try (OutputStream out = exchange.getResponseBody()) {
			out.write(body);
		}
	}

	private void serveJson(HttpExchange exchange, Map<String, Object> payload) throws IOException {
		byte[] body = Json.write(payload).getBytes(StandardCharsets.UTF_8);
		exchange.getResponseHeaders().add("Content-Type", "application/json; charset=utf-8");
		exchange.sendResponseHeaders(200, body.length);
		try (OutputStream out = exchange.getResponseBody()) {
			out.write(body);
		}
		drain(exchange.getRequestBody());
	}

	private void drain(InputStream in) throws IOException {
		try (InputStream stream = in) {
			stream.readAllBytes();
		}
	}

	// ------------------------------------------------------------------ backend

	/** One database, driven through the same SQL, differing only in where the rules run. */
	static final class Backend {
		final String name;
		final String description;
		final boolean useStoredProcedures;
		private final String url;
		private final String user;
		private final String password;

		Backend(String name, String description, boolean useStoredProcedures, String url, String user, String password) {
			this.name = name;
			this.description = description;
			this.useStoredProcedures = useStoredProcedures;
			this.url = url;
			this.user = user;
			this.password = password;
		}

		Connection connect() throws SQLException {
			Connection connection = DriverManager.getConnection(url, user, password);
			connection.setAutoCommit(true);
			return connection;
		}

		/** Clears anything left behind by an earlier run.  Seed rows are untouched. */
		void reset() throws SQLException {
			try (Connection connection = connect()) {
				execute(connection, "DELETE FROM Stock WHERE owner IN (?, ?)", OWNER, SCRATCH);
				execute(connection, "DELETE FROM Portfolio WHERE owner IN (?, ?)", OWNER, SCRATCH);
			}
		}

		Map<String, Object> createPortfolio(String owner, String accountID) throws SQLException {
			try (Connection connection = connect()) {
				execute(connection, "INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions)"
					+ " VALUES (?, 0.0, ?, 'Basic', 50.0, 0.0)", owner, accountID);

				//the scratch portfolio exists purely so the delete step has a portfolio with holdings to cascade
				execute(connection, "INSERT INTO Portfolio (owner, total, accountID, loyalty, balance, commissions)"
					+ " VALUES (?, 2500.0, 'ACCT-9002', 'Basic', 50.0, 0.0)", SCRATCH);
				execute(connection, "INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission)"
					+ " VALUES (?, 'IBM', 10, 250.0, 2500.0, ?, 9.99)", SCRATCH, QUOTE_DATE);

				Map<String, Object> response = new LinkedHashMap<>();
				response.put("portfolio", readPortfolio(connection, owner));
				return response;
			}
		}

		/** A buy (positive shares) or sell (negative shares) at a fixed quote, followed by the
		 *  portfolio refresh that GET /{owner} performs. */
		Map<String, Object> trade(String owner, String symbol, int shares, double price) throws SQLException {
			try (Connection connection = connect()) {
				double tradeValue = Math.abs(shares) * price;
				double commission = applyCommission(connection, owner, tradeValue);

				Map<String, Object> existing = readStock(connection, owner, symbol);
				boolean closed = false;

				if (existing.isEmpty()) {
					execute(connection, "INSERT INTO Stock (owner, symbol, shares, price, total, dateQuoted, commission)"
						+ " VALUES (?, ?, ?, ?, ?, ?, ?)",
						owner, symbol, shares, price, shares * price, QUOTE_DATE, commission);
				} else {
					int newShares = ((Number) existing.get("shares")).intValue() + shares;
					double newCommission = ((Number) existing.get("commission")).doubleValue() + commission;

					if (newShares > 0) {
						execute(connection, "UPDATE Stock SET shares = ?, price = ?, total = ?, dateQuoted = ?, commission = ?"
							+ " WHERE owner = ? AND symbol = ?",
							newShares, price, newShares * price, QUOTE_DATE, newCommission, owner, symbol);
					} else {
						execute(connection, "DELETE FROM Stock WHERE owner = ? AND symbol = ?", owner, symbol);
						closed = true;
					}
				}

				Map<String, Object> refreshed = refresh(connection, owner);

				Map<String, Object> response = new LinkedHashMap<>();
				response.put("symbol", symbol);
				response.put("shares", shares);
				response.put("tradeValue", tradeValue);
				response.put("commission", commission);
				response.put("positionClosed", closed);
				response.put("loyalty", refreshed.get("loyalty"));
				response.put("portfolio", refreshed);
				return response;
			}
		}

		Map<String, Object> fetchPortfolio(String owner) throws SQLException {
			try (Connection connection = connect()) {
				Map<String, Object> portfolio = refresh(connection, owner);

				Map<String, Object> response = new LinkedHashMap<>();
				response.put("portfolio", portfolio);
				response.put("holdings", readStocks(connection, owner));
				//"returns" as the trader sees them: holdings plus cash, less everything paid in commission
				double netWorth = asDouble(portfolio.get("total")) + asDouble(portfolio.get("balance"));
				response.put("netWorth", round(netWorth));
				response.put("commissionsPaid", portfolio.get("commissions"));
				return response;
			}
		}

		Map<String, Object> deletePortfolio(String owner) throws SQLException {
			try (Connection connection = connect()) {
				int stocksBefore = count(connection, "SELECT COUNT(*) FROM Stock WHERE owner = ?", owner);
				int deleted = execute(connection, "DELETE FROM Portfolio WHERE owner = ?", owner);
				int stocksAfter = count(connection, "SELECT COUNT(*) FROM Stock WHERE owner = ?", owner);

				Map<String, Object> response = new LinkedHashMap<>();
				response.put("owner", owner);
				response.put("portfoliosDeleted", deleted);
				response.put("stockRowsBefore", stocksBefore);
				response.put("stockRowsAfterCascade", stocksAfter);
				response.put("portfolioStillPresent", !readPortfolio(connection, owner).isEmpty());
				return response;
			}
		}

		/** Recomputes the portfolio total from its holdings and re-tiers the loyalty level. */
		private Map<String, Object> refresh(Connection connection, String owner) throws SQLException {
			double total = 0.0;
			for (Object holding : readStocks(connection, owner)) {
				@SuppressWarnings("unchecked")
				Map<String, Object> stock = (Map<String, Object>) holding;
				total += asDouble(stock.get("total"));
			}

			execute(connection, "UPDATE Portfolio SET total = ? WHERE owner = ?", round(total), owner);
			updateLoyaltyLevel(connection, owner, round(total));

			return readPortfolio(connection, owner);
		}

		/** DB2 keeps this in CALCULATE_COMMISSION; PostgreSQL runs the lifted CommissionRules. */
		private double applyCommission(Connection connection, String owner, double tradeValue) throws SQLException {
			if (useStoredProcedures) {
				try (CallableStatement procedure = connection.prepareCall("CALL CALCULATE_COMMISSION(?, ?, ?)")) {
					procedure.setString(1, owner);
					procedure.setDouble(2, tradeValue);
					procedure.registerOutParameter(3, Types.DOUBLE);
					procedure.execute();
					return round(procedure.getDouble(3));
				}
			}

			String loyalty = (String) readPortfolio(connection, owner).get("loyalty");
			double commission = round(CommissionRules.commissionFor(loyalty, tradeValue));
			execute(connection, "UPDATE Portfolio SET commissions = COALESCE(commissions, 0) + ?,"
				+ " balance = COALESCE(balance, 0) - ? WHERE owner = ?", commission, commission, owner);
			return commission;
		}

		/** DB2 keeps this in UPDATE_LOYALTY_LEVEL; PostgreSQL runs the lifted LoyaltyRules. */
		private String updateLoyaltyLevel(Connection connection, String owner, double total) throws SQLException {
			if (useStoredProcedures) {
				try (CallableStatement procedure = connection.prepareCall("CALL UPDATE_LOYALTY_LEVEL(?, ?, ?)")) {
					procedure.setString(1, owner);
					procedure.setDouble(2, total);
					procedure.registerOutParameter(3, Types.VARCHAR);
					procedure.execute();
					return procedure.getString(3);
				}
			}

			String loyalty = LoyaltyRules.levelFor(total);
			execute(connection, "UPDATE Portfolio SET loyalty = ? WHERE owner = ?", loyalty, owner);
			return loyalty;
		}

		/** Every Portfolio and Stock row in this database, keyed for row-level reconciliation. */
		Map<String, Map<String, Object>> snapshot() throws SQLException {
			Map<String, Map<String, Object>> rows = new LinkedHashMap<>();

			try (Connection connection = connect()) {
				try (PreparedStatement query = connection.prepareStatement(
						"SELECT owner, total, accountID, loyalty, balance, commissions FROM Portfolio ORDER BY owner");
				     ResultSet results = query.executeQuery()) {
					while (results.next()) {
						Map<String, Object> row = new LinkedHashMap<>();
						row.put("total", round(results.getDouble("total")));
						row.put("accountID", results.getString("accountID"));
						row.put("loyalty", results.getString("loyalty"));
						row.put("balance", round(results.getDouble("balance")));
						row.put("commissions", round(results.getDouble("commissions")));
						rows.put("Portfolio/" + results.getString("owner"), row);
					}
				}

				try (PreparedStatement query = connection.prepareStatement(
						"SELECT owner, symbol, shares, price, total, dateQuoted, commission FROM Stock ORDER BY owner, symbol");
				     ResultSet results = query.executeQuery()) {
					while (results.next()) {
						Map<String, Object> row = new LinkedHashMap<>();
						row.put("shares", results.getInt("shares"));
						row.put("price", round(results.getDouble("price")));
						row.put("total", round(results.getDouble("total")));
						row.put("dateQuoted", results.getString("dateQuoted"));
						row.put("commission", round(results.getDouble("commission")));
						rows.put("Stock/" + results.getString("owner") + "/" + results.getString("symbol"), row);
					}
				}
			}

			return rows;
		}

		private Map<String, Object> readPortfolio(Connection connection, String owner) throws SQLException {
			Map<String, Object> portfolio = new LinkedHashMap<>();

			try (PreparedStatement query = connection.prepareStatement(
					"SELECT owner, total, accountID, loyalty, balance, commissions FROM Portfolio WHERE owner = ?")) {
				query.setString(1, owner);
				try (ResultSet results = query.executeQuery()) {
					if (results.next()) {
						portfolio.put("owner", results.getString("owner"));
						portfolio.put("total", round(results.getDouble("total")));
						portfolio.put("accountID", results.getString("accountID"));
						portfolio.put("loyalty", results.getString("loyalty"));
						portfolio.put("balance", round(results.getDouble("balance")));
						portfolio.put("commissions", round(results.getDouble("commissions")));
					}
				}
			}

			return portfolio;
		}

		private Map<String, Object> readStock(Connection connection, String owner, String symbol) throws SQLException {
			Map<String, Object> stock = new LinkedHashMap<>();

			try (PreparedStatement query = connection.prepareStatement(
					"SELECT symbol, shares, price, total, dateQuoted, commission FROM Stock WHERE owner = ? AND symbol = ?")) {
				query.setString(1, owner);
				query.setString(2, symbol);
				try (ResultSet results = query.executeQuery()) {
					if (results.next()) {
						stock.put("symbol", results.getString("symbol"));
						stock.put("shares", results.getInt("shares"));
						stock.put("price", round(results.getDouble("price")));
						stock.put("total", round(results.getDouble("total")));
						stock.put("dateQuoted", results.getString("dateQuoted"));
						stock.put("commission", round(results.getDouble("commission")));
					}
				}
			}

			return stock;
		}

		private List<Object> readStocks(Connection connection, String owner) throws SQLException {
			List<Object> stocks = new ArrayList<>();

			try (PreparedStatement query = connection.prepareStatement(
					"SELECT symbol, shares, price, total, dateQuoted, commission FROM Stock WHERE owner = ? ORDER BY symbol")) {
				query.setString(1, owner);
				try (ResultSet results = query.executeQuery()) {
					while (results.next()) {
						Map<String, Object> stock = new LinkedHashMap<>();
						stock.put("symbol", results.getString("symbol"));
						stock.put("shares", results.getInt("shares"));
						stock.put("price", round(results.getDouble("price")));
						stock.put("total", round(results.getDouble("total")));
						stock.put("dateQuoted", results.getString("dateQuoted"));
						stock.put("commission", round(results.getDouble("commission")));
						stocks.add(stock);
					}
				}
			}

			return stocks;
		}

		private int count(Connection connection, String sql, Object... parameters) throws SQLException {
			try (PreparedStatement query = connection.prepareStatement(sql)) {
				bind(query, parameters);
				try (ResultSet results = query.executeQuery()) {
					return results.next() ? results.getInt(1) : 0;
				}
			}
		}

		private int execute(Connection connection, String sql, Object... parameters) throws SQLException {
			try (PreparedStatement statement = connection.prepareStatement(sql)) {
				bind(statement, parameters);
				return statement.executeUpdate();
			}
		}

		private void bind(PreparedStatement statement, Object... parameters) throws SQLException {
			for (int index = 0; index < parameters.length; index++) {
				statement.setObject(index + 1, parameters[index]);
			}
		}
	}

	private static double asDouble(Object value) {
		return value == null ? 0.0 : ((Number) value).doubleValue();
	}

	/** Money is stored as a double on both engines; round to cents so the JSON reads cleanly. */
	private static double round(double value) {
		return Math.round(value * 100.0) / 100.0;
	}

	// ------------------------------------------------------------------- types

	private interface Action {
		Map<String, Object> apply(Backend backend) throws SQLException;
	}

	private static final class Scenario {
		final String name;
		final String detail;
		final Action action;

		Scenario(String name, String detail, Action action) {
			this.name = name;
			this.detail = detail;
			this.action = action;
		}
	}

	/** Minimal JSON writer, so the harness needs no dependencies beyond the JDBC drivers. */
	static final class Json {
		static String write(Object value) {
			StringBuilder json = new StringBuilder();
			append(json, value);
			return json.toString();
		}

		private static void append(StringBuilder json, Object value) {
			if (value == null) {
				json.append("null");
			} else if (value instanceof Map) {
				json.append('{');
				boolean first = true;
				for (Map.Entry<?, ?> entry : ((Map<?, ?>) value).entrySet()) {
					if (!first) json.append(',');
					first = false;
					quote(json, String.valueOf(entry.getKey()));
					json.append(':');
					append(json, entry.getValue());
				}
				json.append('}');
			} else if (value instanceof Collection) {
				json.append('[');
				boolean first = true;
				for (Object element : (Collection<?>) value) {
					if (!first) json.append(',');
					first = false;
					append(json, element);
				}
				json.append(']');
			} else if (value instanceof Number || value instanceof Boolean) {
				json.append(value);
			} else {
				quote(json, String.valueOf(value));
			}
		}

		private static void quote(StringBuilder json, String text) {
			json.append('"');
			for (char character : text.toCharArray()) {
				switch (character) {
					case '"'  -> json.append("\\\"");
					case '\\' -> json.append("\\\\");
					case '\n' -> json.append("\\n");
					case '\r' -> json.append("\\r");
					case '\t' -> json.append("\\t");
					default   -> {
						if (character < 0x20) json.append(String.format("\\u%04x", (int) character));
						else json.append(character);
					}
				}
			}
			json.append('"');
		}
	}
}
