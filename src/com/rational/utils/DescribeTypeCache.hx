package com.rational.utils;

import flash.Error;
import flash.utils.TypedDictionary;
import flash.xml.XML;
import flash.xml.XMLList;

using Type;

class DescribeTypeCache<T : IDescribeTypeCacheRecord> {
	
	private var recordType:Class<T>;
	private var recordCache:TypedDictionary<String, T>;

	public function new(recordType:Class<T>) {
		this.recordType = recordType;
		recordCache = new TypedDictionary<String, T>();
	}

	public function describeType(value:Dynamic):T {
		var className:String = DescribeTypeTools.getQualifiedClassName(value);
		var record:T;
		if ((record = recordCache.get(className)) != null) {
			return record;
		}
		var typeDescription:XML = DescribeTypeTools.describeType(value);
		record = recordType.createInstance([]);
		record.init(typeDescription);
		recordCache.set(className, record);
		return record;
	}		
}
