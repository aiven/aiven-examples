package aiven;

public class Arguments {
    public String host;
    public int port;
    public String username;
    public String password;
    public String caPath;

    public Arguments(String host, int port, String username, String password, String caPath) {
        this.host = host;
        this.port = port;
        this.username = username;
        this.password = password;
        this.caPath = caPath;
    }
}