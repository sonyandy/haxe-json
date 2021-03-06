package com.rational.serialization.json;

import com.rational.utils.CharCodes;
import com.rational.utils.Tools;
import com.rational.utils.IStream;

using StringTools;

private typedef CC = CharCodes;
private typedef S = LexerStates;
private typedef T = Tools;

class Lexer implements IStream<Token> {
	private var string:String;
	private var index:Int;
	private var peeked:Bool;
	private var token:Null<Token>;
	
	public function new(string:String) {
		this.string = string;
		index = 0;
		peeked = false;
	}
	
	public inline function peek():Null<Token> {
		if (!peeked) {
			token = nextToken();
			peeked = true;
		}
		return token;
	}
	
	public inline function pop():Null<Token> {
		peek();
		peeked = false;
		return token;
	}
	
	public inline function skip():Void {
		pop();
	}
	
	public inline function isEmpty():Bool {
		skipWhitespace();
		return !peeked && index >= string.length;
	}
	
	private inline function safePop(string:String):Int {
		var code;
		if ((code = string.charCodeAt(index++)) == null) {
			throw new LexerError("Unexpected end of input");
		}
		return code;
	}
	
	private function nextToken():Null<Token> {
		var state:Int = S.START;
		var string:String = this.string;
		var code:Null<Int>;
		var buf:StringBuf = null;
		var hexBuf:StringBuf = null;
		skipWhitespace();
		do {
			switch (state) {
				case S.START:
					switch (code = string.charCodeAt(index)) {
						case CC.LEFT_BRACE: index++; return Token.LEFT_BRACE;
						case CC.RIGHT_BRACE: index++; return Token.RIGHT_BRACE;
						case CC.LEFT_BRACKET: index++; return Token.LEFT_BRACKET;
						case CC.RIGHT_BRACKET: index++; return Token.RIGHT_BRACKET;
						case CC.COMMA: index++; return Token.COMMA;
						case CC.COLON: index++; return Token.COLON;
						case CC.t:
							index++;
							buf = new StringBuf();
							buf.addChar(CC.t);
							state = S.t;
						case CC.f:
							index++;
							buf = new StringBuf();
							buf.addChar(CC.f);
							state = S.f;
						case CC.n:
							index++;
							buf = new StringBuf();
							buf.addChar(CC.n);
							state = S.n;
						case CC.QUOTATION_MARK:
							index++;
							buf = new StringBuf();
							quotedString(buf);
							return Token.STRING(buf.toString());
						case CC.MINUS:
							index++;
							buf = new StringBuf();
							buf.addChar(CC.MINUS);
							state = S.MINUS;
						default: switch (Std.int(code - CC.ZERO)) {
							case 0:
								index++;
								buf = new StringBuf();
								buf.addChar(CC.ZERO);
								state = S.LEADING_ZERO;
							case 1, 2, 3, 4, 5, 6, 7, 8, 9:
								index++;
								buf = new StringBuf();
								buf.addChar(code);
								state = S.INTEGRAL;
							default: return null;
						}
					}
				case S.t:
					(char(CC.r, buf) && char(CC.u, buf) && char(CC.e, buf)) || unexpected(buf);
					return Token.TRUE;
				case S.f:
					(char(CC.a, buf) && char(CC.l, buf) && char(CC.s, buf) && char(CC.e, buf)) || unexpected(buf);
					return Token.FALSE;
				case S.n:
					(char(CC.u, buf) && char(CC.l, buf) && char(CC.l, buf)) || unexpected(buf);
					return Token.NULL;
				case S.MINUS:
					switch (Std.int((code = string.charCodeAt(index)) - CC.ZERO)) {
						case 0:
							index++;
							buf.addChar(CC.ZERO);
							state = S.LEADING_ZERO;
						case 1, 2, 3, 4, 5, 6, 7, 8, 9:
							index++;
							buf.addChar(code);
							state = S.INTEGRAL;
						default: unexpected(buf);
					}
				case S.LEADING_ZERO:
					state = fractional(buf) ? S.FRACTIONAL 
						: exponential(buf) ? S.EXPONENTIAL 
						: S.NUMBER;
				case S.INTEGRAL:
					many(digit, buf); 
					state = fractional(buf) ? S.FRACTIONAL 
						: exponential(buf) ? S.EXPONENTIAL 
						: S.NUMBER;
				case S.FRACTIONAL:
					some(digit, buf) || unexpected(buf);
					state = exponential(buf) ? S.EXPONENTIAL : S.NUMBER;
				case S.EXPONENTIAL:
					char(CC.PLUS, buf) || char(CC.MINUS, buf);
					some(digit, buf) || unexpected(buf);
					state = S.NUMBER;
				case S.NUMBER: return Token.NUMBER(T.parseFloat(buf.toString()));
				default: throw new LexerError("Internal error");
			}
		} while (true);
		throw new LexerError("Internal error");
	}
	
	private inline function quotedString(buf:StringBuf):Void {
		var quoteIndex:Int = index;
		do {
			quoteIndex = string.indexOf("\"", quoteIndex);
			
			if (quoteIndex >= 0) {
				var backspaceCount:Int = 0;
				var backspaceIndex:Int = quoteIndex - 1;
				while (string.charCodeAt(backspaceIndex) == CC.REVERSE_SOLIDUS) {
					backspaceCount++;
					backspaceIndex--;
				}
				if (backspaceCount % 2 == 0) {
					break;
				}
				quoteIndex++;
			} else {
				throw new LexerError("Unterminated string literal");
			}
		} while (true);
		unescapeString(string.substr(index, quoteIndex - index), buf);
		index = quoteIndex + 1;
	}
	
	private static inline function unescapeString(input:String, buf:StringBuf):Void {		
		var backslashIndex:Int = 0;
		var nextSubstringStartPosition:Int = 0;
		var len:Int = input.length;
		do {
			backslashIndex = input.indexOf("\\", nextSubstringStartPosition);
			if (backslashIndex >= 0) {
				buf.addSub(input, nextSubstringStartPosition, backslashIndex - nextSubstringStartPosition);
				nextSubstringStartPosition = backslashIndex + 2;
				
				var afterBackslashIndex:Int = backslashIndex + 1;
				var escapedCharCode:Int = input.charCodeAt(afterBackslashIndex);
				switch (escapedCharCode) {	
					case CC.QUOTATION_MARK: buf.addChar(CC.QUOTATION_MARK);
					case CC.REVERSE_SOLIDUS: buf.addChar(CC.REVERSE_SOLIDUS);
					case CC.n: buf.addChar(CC.NEWLINE);
					case CC.r: buf.addChar(CC.CARRIAGE_RETURN);
					case CC.t: buf.addChar(CC.HORIZONTAL_TAB);	
					
					case CC.u:						
						if (nextSubstringStartPosition + 4 > len) {
							throw new LexerError("Unexpected end of input.  Expecting 4 hex digits after \\u.");
						}
						
						var hexBuf:StringBuf = new StringBuf();
						for (i in nextSubstringStartPosition...nextSubstringStartPosition + 4) {
							var possibleHexCharCode:Int = input.charCodeAt(i);
							if (!isHexDigit(possibleHexCharCode)) {
								throw new LexerError("Excepted a hex digit, but found: " + input.charAt(i));
							}
							
							hexBuf.addChar(possibleHexCharCode);
						}
						
						buf.addChar(T.parseHex(hexBuf.toString()));

						nextSubstringStartPosition += 4;
					
					case CC.f: buf.addChar(CC.FORMFEED);
					case CC.SOLIDUS: buf.addChar(CC.SOLIDUS);
					case CC.b: buf.addChar(CC.BELL);
					default: throw new LexerError("Unexpected " + input.charAt(afterBackslashIndex));
				}
			}
			else {
				buf.addSub(input, nextSubstringStartPosition);
				break;
			}
		} while (nextSubstringStartPosition < len);
	}
	
	private static inline function isHexDigit(code:Int):Bool {
		return isDigit(code) || (code >= CC.A && code <= CC.F) || (code >= CC.a && code <= CC.f);
	}
	
	private static inline function isDigit(code:Int):Bool {
		return code >= CC.ZERO && code <= CC.NINE;
	}
	
	private inline function fractional(buf:StringBuf):Bool {
		return char(CC.PERIOD, buf);
	}
	
	private inline function exponential(buf:StringBuf):Bool {
		return char(CC.e, buf) || char(CC.E, buf);
	}
	
	private inline function some(f:StringBuf -> Bool, buf:StringBuf):Bool {
		return f(buf) && many(f, buf);
	}
	
	private inline function many(f:StringBuf -> Bool, buf:StringBuf):Bool {
		while (f(buf)) {}
		return true;
	}
	
	private function char(code:Int, buf:StringBuf):Bool {
		if (string.charCodeAt(index) != code) {
			return false;
		}
		index++;
		buf.addChar(code);
		return true;
	}
	
	private function digit(buf:StringBuf):Bool {
		var code:Null<Int>;
		if ((code = string.charCodeAt(index)) == null) {
			return false;
		}
		switch (Std.int(code - CC.ZERO)) {
			case 0, 1, 2, 3, 4, 5, 6, 7, 8, 9:
				index++;
				buf.addChar(code);
				return true;
			default: return false;
		}
	}
	
	private inline function skipWhitespace():Void {
		while (true) {
			switch (string.charCodeAt(index)) {
				case CC.SPACE, CC.HORIZONTAL_TAB, CC.NEWLINE, CC.CARRIAGE_RETURN:
					index++;
				default:
					break;
			}
		}
	}
	
	private inline function unexpected(buf:StringBuf):Bool {
		var code:Null<Int>;
		if ((code = string.charCodeAt(index++)) == null) {
			throw new LexerError("Unexpected end of input");
		}
		buf.addChar(code);
		throw new LexerError("Unexpected " + buf.toString());
		return true;
	}
}
