
import js.Browser.console;
import js.Browser.document;
import js.Browser.window;
import js.Node.process;
import js.node.ChildProcess.spawn;

class App {

    static inline function setText( id : String, text : String ) {
        document.getElementById( id ).textContent = text;
    }

    static function main() {

        window.onload = function() {

            document.getElementById( 'logo-haxe' ).style.opacity = '1';

            setText( 'system', process.platform +' '+ process.arch );
            setText( 'node', 'node '+process.version );
            setText( 'electron', 'electron '+process.versions['electron'] );

            spawn( 'haxe', ['-version'] ).stderr.on( 'data', function(buf) {
                setText( 'haxe', 'haxe $buf' );
            });
        }
    }

}
