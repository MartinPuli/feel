from chalk.sql import PostgreSQLSource

# The Postgres behind SUPABASE_URL in chalk/.env, registered in the Chalk dashboard as a PostgreSQL data
# source named "feel_finds" (Data Sources -> Add -> PostgreSQL). Credentials stay in Chalk, never in code.
feel_finds = PostgreSQLSource(name="feel_finds")
