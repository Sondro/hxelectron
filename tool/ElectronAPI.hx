
import haxe.macro.Expr;

using StringTools;

@:enum abstract APIType(String) from String to String {
	var Module = "Module";
	var Class_ = "Class";
	var Structure = "Structure";
}

@:enum abstract APIPlatform(String) from String to String {
	var macOS = "macOS";
	var windows = "Windows";
	var linux = "LINUX";
	var experimental = "Experimental";
}

typedef APIProperty = {
	name : String,
	type : String,
	collection: Bool,
	?description : String,
	?properties : Array<APIProperty>
}

typedef APIEvent = {
	name : String,
	?description : String,
	?platforms : Array<APIPlatform>,
	returns : Array<APIReturn>
}

typedef APIMethodParameter = {
	name : String,
	type : String,
	description : String,
	properties : Array<APIProperty>,
	collection: Bool,
	required: Null<Bool>,
}

typedef APIReturn = {
	name : String,
	type : String,
	collection: Bool,
	description : String,
	?properties : Array<APIProperty>,
	required: Null<Bool>,
}

typedef APIMethod = {
	name : String,
	signature : String,
	description : String,
	returns : APIReturn,
	parameters : Array<APIMethodParameter>,
	platforms : Array<APIPlatform>
}

typedef APIProcess = {
	var main : Bool;
	var renderer : Bool;
}

typedef APIItem = {
	name : String,
	description : String,
	process : APIProcess,
	version : String,
	type : APIType,
	slug : String,
	websiteUrl : String,
	repoUrl : String,
	methods : Array<APIMethod>,
	?instanceEvents : Array<APIEvent>,
	?instanceName : String,
	?instanceProperties : Array<APIProperty>,
	?instanceMethods : Array<APIMethod>,
	?constructorMethod : APIMethod,
	?staticMethods : Array<APIMethod>,
	?properties : Array<APIProperty>,
	?events : Array<APIEvent>,
};

/**
	Generates extern type definitions from electron-api.json
**/
class ElectronAPI {

	static var KWDS = ['class','switch'];

	public static var pos(default,null) = #if macro null #else { min: 0, max: 0, file: '' } #end;

	static var _api : Array<APIItem>;

	public static function build( api : Array<APIItem>, ?pack : Array<String> ) : Array<TypeDefinition> {

		_api = api;

		if( pack == null ) pack = ['electron'];

		var types = new Array<TypeDefinition>();

		for( item in api ) {
			var ntypes = convertItem( item, pack );
			for( ntype in ntypes ) {
				if( ntype == null )
					ntypes.remove( ntype );
			}
			types = types.concat( ntypes );
		}

		var i = 0, j = 0;
		while( i < types.length ) {
			j = 0;
			while( j < types.length ) {
				if( i != j ) {
					var ti = types[i];
					var tj = types[j];
					if( ti.name == tj.name &&
						ti.pack.join( '.' ) == tj.pack.join( '.' ) ) {
						tj.fields = tj.fields.concat( ti.fields );
						types.splice( i, 1 );
						break;
					}
				}
				j++;
			}
			i++;
		}

		///// PATCH ////////////////////////////////////////////////////////////

		for( type in types ) {
			switch type.name {
			case 'Screen':
				// TODO: https://github.com/fponticelli/hxelectron/issues/29
				for( i in 0...type.meta.length ) {
					if( type.meta[i].name == ':jsRequire' ) {
						type.meta.splice( i, 1 );
						type.meta.push( { name: ':native', params: [macro 'require("electron").screen'], pos: pos } );
						break;
					}
				}
			case 'App':
				type.fields.push( {
					name: 'on',
					access: [AStatic],
					kind: FFun( { args: [
						{ name: 'eventType', type: macro:Dynamic },
						{ name: 'callback', type: macro:Dynamic->Void }
					], ret: macro: Void, expr: null } ),
					pos: pos
				} );
			case 'Remote':
				var manipulateReturn = function(f:Field) {
					switch f.kind {
					case FFun(f):
						switch f.ret {
						case TPath(p): p.pack = ['electron','main'];
						default:
						}
					default:
					}
				}
				for( f in type.fields ) {
					switch f.name {
					case 'getCurrentWindow','getCurrentWebContents': manipulateReturn(f);
					}
				}
			}
		}

		//types.push( createAlias( 'Any', pack ) );
		types.push( createAlias( 'MenuItemConstructorOptions', pack ) );
		types.push( createTypeDefinition( pack, 'Accelerator', TDAbstract( macro:String, [macro:String], [macro:String] ) ) );

		////////////////////////////////////////////////////////////////////////

		return types;
	}

	static function convertItem( item : APIItem, pack : Array<String> ) : Array<TypeDefinition> {

		var pack = pack.copy();
		var meta = [];

		if( item.process != null && (!item.process.main || !item.process.renderer) ) {
			if( item.process.main ) {
				pack.push( 'main' );
				//meta.push( { name: ':electron_main', pos: pos } );
				//meta.push( { name: ':require', params: [macro $i{'electron_main'}], pos: pos } );
			} else if( item.process.renderer ) {
				pack.push( 'renderer' );
				//meta.push( { name: ':electron_renderer', pos: pos } );
				//meta.push( { name: ':require', params: [macro $i{'electron_renderer'}], pos: pos } );
			}
		}

		var fields = new Array<Field>();
		var extraTypes = new Array<TypeDefinition>();

		if( item.properties != null ) {
			for( p in item.properties ) {
				//TODO hack to check if field is optional
				var meta = (p.description != null && p.description.startsWith( '(optional)' ) ) ? [{ name: ':optional', pos: pos }] : [];
				fields.push( createField( p.name, FVar( convertType( p.type, p.properties, p.collection ) ), p.description, meta ) );
			}
		}

		var def = switch item.type {

		case Class_:
			var sup : TypePath = null;
			if( item.instanceEvents != null ) {
				sup = {
					pack: ['js','node','events'], name: 'EventEmitter',
					params: [TPType( TPath( { name: item.name, pack: pack } ) )]
				};
				extraTypes.push( createEventAbstract( pack, item.name, item.instanceEvents ) );
			}
			if( item.instanceProperties != null )
				for( p in item.instanceProperties )
					fields.push( createField( p.name, FVar( convertType( p.type, false ) ), p.description ) );
			if( item.constructorMethod != null )
				fields.push( convertMethod( item.constructorMethod ) );
			if( item.instanceMethods != null )
				for( m in item.instanceMethods )
					fields.push( convertMethod( m ) );
			if( item.staticMethods != null )
				for( m in item.staticMethods )
					fields.push( convertMethod( m, [AStatic] ) );
			createClassTypeDefinition( pack, item.name, sup, fields, meta );

		case Module:
			var sup : TypePath = null;
			if( item.methods != null ) {
				//TODO hack
				var alreadyAdded = false;
				for( m in item.methods ) {
					for( f in fields ) {
						if( f.name == m.name ) {
							trace( 'WARNING Duplicate module method name: '+item.name+'.'+m.name );
							alreadyAdded = true;
							break;
						}
					}
					if( !alreadyAdded ) fields.push( convertMethod( m, [AStatic] ) );
				}
			}
			createClassTypeDefinition( pack, item.name, sup, fields, meta );

		case Structure:
			createTypeDefinition( pack, item.name, TDStructure, fields, meta );
		}

		return [def].concat( extraTypes );
	}

	static function convertMethod( method : APIMethod, ?access : Array<Access> ) : Field {

		var ret = macro : Void;
		if( method.returns != null )
			ret = convertType( method.returns.type, method.returns.properties, method.returns.collection );

		var args = new Array<FunctionArg>();
		if( method.parameters != null ) {
			for( p in method.parameters ) {
				var type = if( Std.is( p.type, Array ) ) 'Object' else p.type;
				switch p.name {
				case '...args':
					args.push( {
						name: 'args',
						type: macro:haxe.extern.Rest<Any>,
						opt: false // Haxe doesnt allow rest args to be optional.
					} );
				default:
					args.push( {
						name: escapeName( p.name ),
						type: convertType( type, p.properties, p.collection ),
						// Check `required` for pre `1.4.8` json files, fall back description check if field is optional.
						opt: p.required != null ? !p.required : p.description != null && p.description.startsWith( '(optional)')
					} );
				}
			}
		}

		var meta = new Array<MetadataEntry>();
		if( method.platforms != null ) {
			var params = new Array<Expr>();
			for( p in method.platforms )
				params.push( { expr: EConst( CString( p ) ), pos: pos } );
			meta.push( { name: ':electron_platform', params: [{ expr: EArrayDecl( params ), pos: pos }], pos: pos } );
		}

		return createField(
			(method.name == null) ? 'new' : method.name,
			FFun( { args: args, ret: ret, expr: null } ),
			access,
			method.description,
			meta
		);
	}

	static function convertType( type : String, ?properties : Array<Dynamic>, collection : Bool ) : ComplexType {

		if( type == null )
			return macro : Dynamic;

		type = Std.string(type);

		inline function isKnownType(type:String):Bool {
			var known = ['Bool','Boolean','Buffer','Event','Error','Int','Integer','Dynamic','Double','Float','Number','Function','Object','Promise','String','URL'];
			return known.indexOf(type) > -1;
		}

		inline function findMatch( type : String ) : Null<{name:String,pack:Array<String>}> {
			var result = null;
			for( item in _api ) if( item.name == type ) {
				result = { name: item.name, pack: ['electron'] };
				if( item.process != null && (!item.process.main || !item.process.renderer) ) {
					if( item.process.main ) {
						result.pack.push( 'main' );
					} else if( item.process.renderer ) {
						result.pack.push( 'renderer' );
					}
				}
				break;
			}
			return result;
		}

		var multiType = if( type.charAt(0) == '[' && type.charAt(type.length-1) == ']' ) {
			var raw = type.substr( 1, type.length-2 ).split( ',' );
			var types = [];
			for( r in raw ) {
				var match = findMatch( r );
				if( match != null ) {
					types.push( TPath( { name: escapeTypeName( match.name ), pack: match.pack } ) );
				} else {
					if( isKnownType( r ) ) {
						types.push( convertType( r, false ) ); //TODO deterrmine 'collection'
					} else {
						// Multiple types might be missing from the json file, we don't want
						// to create haxe.extern.EitherType<Dynamic,Dynamic> or worse ect.
						for( type in types ) switch type {
							case TPath(c) if( c.name != 'Dynamic' ):
								types.push( macro:Dynamic );
								break;
							case _:
								//trace( type );
							}
							if( types.length == 0 ) types.push( macro:Dynamic );
						}
					}
				}
				var result = null;
				if( types.length > 1 ) {
					result = (macro:haxe.extern.EitherType);
					var current = result;
					for( i in 0...types.length ) {
						var t = types[i];
						switch current {
						case TPath(c):
							if( c.params.length >= 1 && i < types.length-1 ) {
								t = TPath( { name: 'EitherType', pack: ['haxe', 'extern'], params: [ TPType(t) ] } );
							}
						case _:
						}
						switch current {
						case TPath(c):
							c.params.push( TPType( t ) );
							if( c.params.length >= 2 ) current = t;
						case _:
						}
					}
				} else {
					result = types[0];
				}
				result;
			} else {
				null;
			}

		var ctype = switch type {
			case 'Blob': macro : js.html.Blob;
			case 'Bool','Boolean': macro : Bool;
			case 'Buffer': macro : js.node.Buffer;
			case 'Event': macro : js.html.Event;
			case 'Error': macro : js.Error;
			case 'Dynamic': macro : Dynamic; // Allows to explicit set type to Dynamic
			case 'Double','Float','Number': macro : Float;
			case 'Function':
				if( properties == null ) macro : haxe.Constraints.Function;
				else {
					//TODO
					//for( p in properties ) {
					TFunction(
						[for(p in properties) convertType( p.type, p.properties, false )],
						macro : Dynamic
					);
				}
			case 'Int','Integer': macro : Int;
			case 'Object':
				if( properties == null ) macro : Dynamic else {
					//TODO
					/*
					for(p in properties ) {
						trace(p.type);
						var t = convertType( '' + p.type, p.properties, p.collection );
						trace(t);
					}
					*/
					TAnonymous( [for(p in properties){
						name: escapeName( p.name ),
						kind: FVar( convertType( '' + p.type, p.properties, p.collection ) ),
						meta: [ { name: ":optional", pos: pos } ], //TODO
						pos: pos,
						doc: p.description
					}] );
				}
			case 'Promise': macro : js.Promise<Dynamic>;
			case 'String','URL': macro : String;
			case 'True','true': macro : Bool; // TODO HACK
			case 'ReadableStream': macro : Dynamic; // TODO HACK
			case 'TouchBarItem': macro : Dynamic; // TODO HACK
			case _ if( multiType != null ): multiType;
			default: TPath( { pack: [], name: escapeTypeName( type ) } );
		}

		return if( collection ) switch ctype {
			case TPath(p): TPath( { name: 'Array<${p.name}>', pack: [] } );
			default: throw 'failed to convert array type';
		} else ctype;
	}

	static function createAlias( name : String, pack : Array<String>, ?type : ComplexType ) : TypeDefinition {
		return createTypeDefinition( pack, name, TDAlias( (type == null) ? macro:Dynamic : type ) );
	}

	static inline function createField( name : String, kind: FieldType, ?access : Array<Access>, ?doc : String, ?meta : Metadata ) : Field {
		var exp = ~/^([0-9]+).+/;
		if( exp.match( name ) ) {
			var v = '"'+name+'"';
			meta.push({
				name: ':native',
				params: [macro $i{'"'+name+'"'}],
				pos: pos
			});
			name = '_$name';
		}
		return {
			access: access,
			name: name,
			kind: kind,
			doc: doc,
			meta: meta,
			pos: pos
		}
	}

	static function createTypeDefinition( pack : Array<String>, name : String, kind : TypeDefKind, ?fields : Array<Field>, ?meta : Metadata, ?isExtern : Bool ) : TypeDefinition {
		var _meta = [{ name: ':require', params: [macro $i{'js'},macro $i{'electron'}], pos: pos }];
		if( meta != null ) _meta = _meta.concat( meta );
		return {
			pack: pack,
			name: escapeTypeName( name ),
			kind: kind,
			fields: (fields == null) ? [] : fields,
			meta: _meta,
			isExtern: isExtern,
			pos: pos
		};
	}

	static function createClassTypeDefinition( pack : Array<String>, name : String, sup : TypePath, ?fields : Array<Field>, ?meta : Metadata ) : TypeDefinition {
		var _meta = [{
			name: ":jsRequire",
			params: [
				{ expr: EConst( CString( 'electron' ) ), pos: pos },
				{ expr: EConst( CString( name ) ), pos: pos }
			],
			pos: pos
		}];
		if( meta != null ) _meta = _meta.concat( meta );
		return createTypeDefinition( pack, name, TDClass( sup ), fields, _meta, true );
	}

	static function createEventAbstract( pack : Array<String>, name : String, events : Array<APIEvent> ) : TypeDefinition {

		var _name = escapeTypeName( name );
		var _pack = pack.copy();
		_pack.push( _name );

		var fields = new Array<Field>();
		for( e in events ) {
			var params = new Array<TypeParam>();
			if( e.returns == null ) {
				params.push( TPType(macro:Void->Void) );
			} else {
				var args = [];
				for( r in e.returns ) {
					var t = convertType( r.type, r.collection );
					if( !r.required ) t = TOptional(t);
					args.push( t );
				}
				params.push( TPType( TFunction( args, macro:Void ) ) );
			}

			var typePath = { pack: _pack, name: _name+'Event', params: params };
			fields.push({
				name: e.name.replace( '-', '_' ),
				kind: FVar( TPath( typePath ), { expr: EConst( CString( e.name ) ), pos: pos } ),
				doc: e.description,
				pos: pos
			});
		}

		return {
			pack: _pack,
			name: _name+'Event',
			params: [ { name: 'T', constraints: [macro:haxe.Constraints.Function] } ],
			kind: TDAbstract(macro:js.node.events.EventEmitter.Event<T>,[],[macro:js.node.events.EventEmitter.Event<T>]),
			fields: fields,
			meta: [
				{ name: ':require', params: [macro $i{'js'},macro $i{'electron'}], pos: pos },
				{ name: ":enum", pos: pos }
			],
			pos: pos
		};
	}

	static function escapeTypeName( name : String ) : String
		return name.charAt( 0 ).toUpperCase() + name.substr( 1 );

	static function escapeName( name : String ) : String
		return (KWDS.indexOf( name ) != -1) ? name+'_' : name;

}
