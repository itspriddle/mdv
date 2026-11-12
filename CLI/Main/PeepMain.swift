// The `mdv` executable; the command lives in MdvCLIKit so tests can run it in-process.
import MdvCLIKit

@main
enum MdvMain {
    static func main() async {
        await MdvCommand.main()
    }
}
