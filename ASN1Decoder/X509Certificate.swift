//
//  X509Certificate.swift
//
//  Copyright © 2017 Filippo Maguolo.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy
//  of this software and associated documentation files (the "Software"), to deal
//  in the Software without restriction, including without limitation the rights
//  to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
//  copies of the Software, and to permit persons to whom the Software is
//  furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all
//  copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
//  IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
//  FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
//  AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
//  LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
//  OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
//  SOFTWARE.

import Foundation

public class X509Certificate: CustomStringConvertible {
    private let asn1: [ASN1Object]
    private let block1: ASN1Object

    private static let beginPemBlock = "-----BEGIN CERTIFICATE-----"
    private static let endPemBlock   = "-----END CERTIFICATE-----"

    private let OID_KeyUsage = "2.5.29.15"
    private let OID_ExtendedKeyUsage = "2.5.29.37"
    private let OID_SubjectAltName = "2.5.29.17"
    private let OID_IssuerAltName = "2.5.29.18"

    enum X509BlockPosition : Int {
        case version = 0
        case serialNumber = 1
        case signatureAlg = 2
        case issuer = 3
        case dateValidity = 4
        case subject = 5
        case publicKey = 6
        case extensions = 7
    }

    public convenience init(data: Data) throws {
        if String(data: data, encoding: .utf8)?.contains(X509Certificate.beginPemBlock) ?? false {
            try self.init(pem: data)
        } else {
            try self.init(der: data)
        }
    }

    public init(der: Data) throws {
        asn1 = try ASN1DERDecoder.decode(data: der)
        guard asn1.count > 0,
            let block1 = asn1.first?.sub(0) else {
                throw ASN1Error.parseError
        }

        self.block1 = block1
    }

    public convenience init(pem: Data) throws {
        guard let derData = X509Certificate.decodeToDER(pem: pem) else {
            throw ASN1Error.parseError
        }

        try self.init(der: derData)
    }

    init(asn1: ASN1Object) throws {
        guard let block1 = asn1.sub(0) else { throw ASN1Error.parseError }

        self.asn1 = [asn1]
        self.block1 = block1
    }

    public var description: String {
        return asn1.reduce("") { $0 + "\($1.description)\n" }
    }

    public var encodedTBSCertificate:Data? {
        var length = UInt16(self.block1.rawValue!.count).bigEndian
        return Data([UInt8(0x30),UInt8(0x82)]) + Data(bytes: &length, count: 2) + (self.block1.rawValue ?? Data())
    }
    
    public var encodedCertificate:Data? {
        var length = UInt16(self.asn1[0].rawValue!.count).bigEndian
        return Data([UInt8(0x30),UInt8(0x82)]) + Data(bytes: &length, count: 2) + (self.asn1[0].rawValue ?? Data())
    }
    
    
    /// Checks that the given date is within the certificate's validity period.
    public func checkValidity(_ date: Date = Date()) -> Bool {
        if let notBefore = notBefore, let notAfter = notAfter {
            return date > notBefore && date < notAfter
        }
        return false
    }

    /// Gets the version (version number) value from the certificate.
    public var version: Int? {
        if let v = firstLeafValue(block: block1) as? Data, let i = v.toIntValue() {
            return Int(i) + 1
        }
        return nil
    }

    /// Gets the serialNumber value from the certificate.
    public var serialNumber: Data? {
        return block1[X509BlockPosition.serialNumber]?.value as? Data
    }


    /// Returns the issuer (issuer distinguished name) value from the certificate as a String.
    public var issuerDistinguishedName: String? {
        if let issuerBlock = block1[X509BlockPosition.issuer] {
            return blockDistinguishedName(block: issuerBlock)
        }
        return nil
    }

    public var issuerOIDs: [String] {
        var result: [String] = []
        if let subjectBlock = block1[X509BlockPosition.issuer] {
            for sub in subjectBlock.sub ?? [] {
                if let value = firstLeafValue(block: sub) as? String {
                    result.append(value)
                }
            }
        }
        return result
    }

    public func issuer(oid: String) -> String? {
        if let subjectBlock = block1[X509BlockPosition.issuer] {
            if let oidBlock = subjectBlock.findOid(oid) {
                return oidBlock.parent?.sub?.last?.value as? String
            }
        }
        return nil
    }
    
    public func issuer(dn: ASN1DistinguishedNames) -> String? {
        return issuer(oid: dn.oid)
    }

    /// Returns the subject (subject distinguished name) value from the certificate as a String.
    public var subjectDistinguishedName: String? {
        if let subjectBlock = block1[X509BlockPosition.subject] {
            return blockDistinguishedName(block: subjectBlock)
        }
        return nil
    }

    public var subjectOIDs: [String] {
        var result: [String] = []
        if let subjectBlock = block1[X509BlockPosition.subject] {
            for sub in subjectBlock.sub ?? [] {
                if let value = firstLeafValue(block: sub) as? String {
                    result.append(value)
                }
            }
        }
        return result
    }

    public func subject(oid: String) -> String? {
        if let subjectBlock = block1[X509BlockPosition.subject] {
            if let oidBlock = subjectBlock.findOid(oid) {
                return oidBlock.parent?.sub?.last?.value as? String
            }
        }
        return nil
    }
    
    public func subject(dn: ASN1DistinguishedNames) -> String? {
        return subject(oid: dn.oid)
    }

    /// Gets the notBefore date from the validity period of the certificate.
    public var notBefore: Date? {
        return block1[X509BlockPosition.dateValidity]?.sub(0)?.value as? Date
    }

    /// Gets the notAfter date from the validity period of the certificate.
    public var notAfter: Date? {
        return block1[X509BlockPosition.dateValidity]?.sub(1)?.value as? Date
    }

    /// Gets the signature value (the raw signature bits) from the certificate.
    public var signature: Data? {
        return asn1[0].sub(2)?.value as? Data
    }

    /// Gets the signature algorithm name for the certificate signature algorithm.
    public var sigAlgName: String? {
        return ASN1Object.oidDecodeMap[sigAlgOID ?? ""]
    }

    /// Gets the signature algorithm OID string from the certificate.
    public var sigAlgOID: String? {
        return block1.sub(2)?.sub(0)?.value as? String
    }

    /// Gets the DER-encoded signature algorithm parameters from this certificate's signature algorithm.
    public var sigAlgParams: Data? {
        return nil
    }

    
    
    
    /**
     Gets a boolean array representing bits of the KeyUsage extension, (OID = 2.5.29.15).
     ```
     KeyUsage ::= BIT STRING {
     digitalSignature        (0),
     nonRepudiation          (1),
     keyEncipherment         (2),
     dataEncipherment        (3),
     keyAgreement            (4),
     keyCertSign             (5),
     cRLSign                 (6),
     encipherOnly            (7),
     decipherOnly            (8)
     }
     ```
     */
    public var keyUsage: [Bool] {
        var result: [Bool] = []
        if let oidBlock = block1.findOid(OID_KeyUsage) {
            let data = oidBlock.parent?.sub?.last?.sub(0)?.value as? Data
            let bits: UInt8 = data?.first ?? 0
            for i in 0...7 {
                let value = bits & UInt8(1 << i) != 0
                result.insert(value, at: 0)
            }
        }
        return result
    }

    /// Gets a list of Strings representing the OBJECT IDENTIFIERs of the ExtKeyUsageSyntax field of the extended key usage extension, (OID = 2.5.29.37).
    public var extendedKeyUsage: [String] {
        return extensionObject(oid: OID_ExtendedKeyUsage)?.valueAsStrings ?? []
    }

    /// Gets a collection of subject alternative names from the SubjectAltName extension, (OID = 2.5.29.17).
    public var subjectAlternativeNames: [String] {
        return extensionObject(oid: OID_SubjectAltName)?.valueAsStrings ?? []
    }

    /// Gets a collection of issuer alternative names from the IssuerAltName extension, (OID = 2.5.29.18).
    public var issuerAlternativeNames: [String] {
        return extensionObject(oid: OID_IssuerAltName)?.valueAsStrings ?? []
    }

    /// Gets the informations of the public key from this certificate.
    public var publicKey: X509PublicKey? {
        return block1[X509BlockPosition.publicKey].map(X509PublicKey.init)
    }

    /// Get a list of critical extension OID codes
    public var criticalExtensionOIDs: [String] {
        guard let extensionBlocks = extensionBlocks else { return [] }
        return extensionBlocks
            .map { X509Extension(block: $0) }
            .filter { $0.isCritical }
            .compactMap { $0.oid }
    }

    /// Get a list of non critical extension OID codes
    public var nonCriticalExtensionOIDs: [String] {
        guard let extensionBlocks = extensionBlocks else { return [] }
        return extensionBlocks
            .map { X509Extension(block: $0) }
            .filter { !$0.isCritical }
            .compactMap { $0.oid }
    }

    private var extensionBlocks: [ASN1Object]? {
        return block1[X509BlockPosition.extensions]?.sub(0)?.sub
    }

    /// Gets the extension information of the given OID code.
    public func extensionObject(oid: String) -> X509Extension? {
        return block1[X509BlockPosition.extensions]?
            .findOid(oid)?
            .parent
            .map(X509Extension.init)
    }

    
    public var basicConstraints:X509ExtBasicContraints {
        return X509ExtBasicContraints(extObject:extensionObject(oid: "2.5.29.19"))
    }
    
    public var authorityKeyIdentifier:X509ExtAuthorityKeyIdentifier {
           return X509ExtAuthorityKeyIdentifier(asn1Object:(extensionObject(oid: "2.5.29.35")?.block)!)
       }
    
    public var subjectKeyIdentifier:Data? {
        return extensionObject(oid: "2.5.29.14")?.block.sub?.last?.sub?.first?.rawValue ?? nil
    }
    
    public var crlDistributionPoints: [X509ExtCrlDistributionPoint] {
         var result: [X509ExtCrlDistributionPoint] = []
        
        guard let crlDistPointsObject = extensionObject(oid: "2.5.29.31") else {
            return result
        }
        
        
        // instance of class
        guard ((crlDistPointsObject.block.sub?.last?.sub?.last?.sub?.last)?.subCount())! > 0 else {
            return result
        }
        
        for crlDistPointObject in ((crlDistPointsObject.block.sub?.last?.sub?.last?.sub!)!) {
            
            result.append(X509ExtCrlDistributionPoint(asn1Object: crlDistPointObject))
        }
        
         return result
     }
     
    
    
    public var certificatePolicies: [X509ExtCertficatePolicy] {
        var result: [X509ExtCertficatePolicy] = []
       
       guard let certficatePoliciesObject = extensionObject(oid: "2.5.29.32") else {
           return result
       }
       
       
       // instance of class
       guard ((certficatePoliciesObject.block.sub?.last?.sub?.last)?.subCount())! > 0 else {
           return result
       }
       
       for certficatePolicyObject in ((certficatePoliciesObject.block.sub?.last?.sub?.last?.sub!)!) {
           
           result.append(X509ExtCertficatePolicy(asn1Object: certficatePolicyObject))
       }
       
        return result
    }
    
    
    // Format subject/issuer information in RFC1779
    private func blockDistinguishedName(block: ASN1Object) -> String {
        var result = ""
        let oidNames: [ASN1DistinguishedNames] = [
            .commonName,
            .dnQualifier,
            .serialNumber,
            .givenName,
            .surname,
            .organizationalUnitName,
            .organizationName,
            .streetAddress,
            .localityName,
            .stateOrProvinceName,
            .countryName,
            .email
        ]
        for oidName in oidNames {
            if let oidBlock = block.findOid(oidName.oid) {
                if !result.isEmpty {
                    result.append(", ")
                }
                result.append(oidName.representation)
                result.append("=")
                if let value = oidBlock.parent?.sub?.last?.value as? String {
                    let specialChar = ",+=\n<>#;\\"
                    let quote = value.contains(where: { specialChar.contains($0) }) ? "\"" : ""
                    result.append(quote)
                    result.append(value)
                    result.append(quote)
                }
            }
        }
        return result
    }

    // read possibile PEM encoding
    private static func decodeToDER(pem pemData: Data) -> Data? {
        if
            let pem = String(data: pemData, encoding: .ascii),
            pem.contains(beginPemBlock) {

            let lines = pem.components(separatedBy: .newlines)
            var base64buffer  = ""
            var certLine = false
            for line in lines {
                if line == endPemBlock {
                    certLine = false
                }
                if certLine {
                    base64buffer.append(line)
                }
                if line == beginPemBlock {
                    certLine = true
                }
            }
            if let derDataDecoded = Data(base64Encoded: base64buffer) {
                return derDataDecoded
            }
        }

        return nil
    }
}

func firstLeafValue(block: ASN1Object) -> Any? {
    if let sub = block.sub?.first {
        return firstLeafValue(block: sub)
    }
    return block.value
}

extension ASN1Object {
    subscript(index: X509Certificate.X509BlockPosition) -> ASN1Object? {
        guard let sub = sub,
            sub.indices.contains(index.rawValue) else { return nil }
        return sub[index.rawValue]
    }
}



 

public class X509ExtCrlDistributionPoint {
    
    var fullName:ASN1GeneralNames?
    var nameRelativeToCRLIssuer:String?
    var reasons:[Bool]?
    var crlIssuer:ASN1GeneralNames?
    
    init(asn1Object: ASN1Object) {
        
        self.fullName = ASN1GeneralNames(asn1Object: (asn1Object.sub?.last?.sub?.last?.sub?.last)!)
        
    }
    
            
            
    //        if let oidBlock = block1.findOid(OID_KeyUsage) {
    //             let data = oidBlock.parent?.sub?.last?.sub(0)?.value as? Data
    //             let bits: UInt8 = data?.first ?? 0
    //             for i in 0...7 {
    //                 let value = bits & UInt8(1 << i) != 0
    //                 result.insert(value, at: 0)
    //             }
    //         }

}


public class X509ExtCertficatePolicy{
    
    var identifier:String?
    var qualifierInfo:X509ExtCertficatePolicyQualifierInfo?
    
    init(asn1Object: ASN1Object) {
        
        self.identifier = (asn1Object.sub?[0].value as! String)
        
        guard asn1Object.subCount() > 1 else {
            return
        }
            
        self.qualifierInfo = X509ExtCertficatePolicyQualifierInfo(asn1Object: (asn1Object.sub?[1])!)
        
    }
}


public class X509ExtCertficatePolicyQualifierInfo {
    
    var identifier:String?
    var qualifier:String?
    
    init(asn1Object: ASN1Object) {
        
        self.identifier = (asn1Object.sub?.first?.sub?.first?.value as! String)
        self.qualifier = (asn1Object.sub?.first?.sub?.last?.value as! String)
        
    }
}





public class X509ExtBasicContraints {
    
    var isCA:Bool? = false
    var pathLengthConstraint:Int? = nil
   

    
    init(extObject: X509Extension?) {
        
        if let cAValue = extObject?.valueAsBlock?.sub?.first?.sub?.first?.value {
            self.isCA = (cAValue as! Bool)
        }
                
        if let pathValue = extObject?.valueAsBlock?.sub?.first?.sub?.last?.value {
            self.pathLengthConstraint = (pathValue as! Int)
        }
    }
}


public class X509ExtAuthorityKeyIdentifier{
    
    var identifier:Data?
    var issuer:ASN1GeneralNames?
    var serialNumber:String?
    
    init(asn1Object: ASN1Object) {
        
        
        guard asn1Object.subCount() > 1 else {
            return
        }
        
        self.identifier = (asn1Object.sub?[1].sub?.first?.sub?.first?.value as! Data)
        
        guard (asn1Object.sub?[1].sub?.first?.subCount())! > 1 else {
            return
        }
        self.issuer = ASN1GeneralNames(asn1Object: (asn1Object.sub?[1].sub?.first?.sub?[1])!)
        
    }
}
