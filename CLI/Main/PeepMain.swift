// The `peep` executable; the command lives in PeepCLIKit so tests can run it in-process.
import PeepCLIKit

@main
enum PeepMain {
    static func main() async {
        await PeepCommand.main()
    }
}
