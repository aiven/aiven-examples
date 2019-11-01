package aiven;

import org.apache.commons.cli.*;

class Cli {
    public static void main(String[] args) throws Exception {
        Arguments parsedArgs = parseArgs(args);
        if (args == null) {
            System.exit(1);
        }
        CassandraExample.cassandraExample(parsedArgs.host, parsedArgs.port, parsedArgs.username, parsedArgs.password, parsedArgs.caPath);
    }

    public static Arguments parseArgs(String[] args) {
        Options options = new Options();

        options.addOption(Option.builder("h")
                .longOpt("host")
                .desc("Cassandra host")
                .required(true)
                .hasArg()
                .build());
        options.addOption(Option.builder("p")
                .longOpt("port")
                .desc("Cassandra port")
                .required(true)
                .hasArg()
                .build());
        options.addOption(Option.builder("u")
                .longOpt("username")
                .desc("Cassandra username")
                .hasArg()
                .build());
        options.addOption(Option.builder("p")
                .longOpt("password")
                .desc("Cassandra password")
                .required(true)
                .hasArg()
                .build());
        options.addOption(Option.builder("c")
                .longOpt("ca-path")
                .desc("Path to cluster CA certificate")
                .required(true)
                .hasArg()
                .build());

        CommandLineParser parser = new DefaultParser();
        HelpFormatter formatter = new HelpFormatter();
        CommandLine cmd = null;
        String username = null;
        try {
            cmd = parser.parse(options, args);
            if (cmd.hasOption("username")) {
                username = cmd.getOptionValue("username");
            } else {
                username = "avnadmin";
            }
            return new Arguments(
                    cmd.getOptionValue("host"),
                    Integer.parseInt(cmd.getOptionValue("port")),
                    username,
                    cmd.getOptionValue("password"),
                    cmd.getOptionValue("ca-path"));
        } catch (NumberFormatException e) {
            formatter.printHelp("aiven-cassandra-example", options);
            System.out.println("\nFailed to parse port, must be an integer value");
        } catch (Exception e) {
            formatter.printHelp("aiven-cassandra-example", options);
        }
        return null;
    }
}