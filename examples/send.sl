// Minimal send: reads SENDBYTE_API_KEY, sends one sandbox email.
import "../src/sendbyte" as sendbyte;
import "proc";

let r = proc.getenv("SENDBYTE_API_KEY");
guard let key = r else {
    println("set SENDBYTE_API_KEY first (sk_test_... is fine)");
    exit(2);
}
let cr = sendbyte.new_client(key);
guard let c = cr else let e = err_of(cr) {
    println("bad key: " + e);
    exit(2);
}
let req = sendbyte.new_email("You <you@yourapp.ng>", sendbyte.to_one("anyone@example.ng"));
req.subject = some("My first SendByte email");
req.html = some("<p>It works.</p>");
let er = sendbyte.send_email(c, req, sendbyte.deadline_in(30));
guard let email = er else let e = err_of(er) {
    println("send failed: " + sendbyte.error_string(e));
    exit(1);
}
println("queued: " + email.id + " (" + email.status + ")");
