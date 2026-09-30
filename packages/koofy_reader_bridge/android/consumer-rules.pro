# Readium 3.1.2 indexes publication services by Class/KClass.simpleName.
# Preserve these small service contracts, including their identity: keepnames alone
# still permits R8 to merge an interface into its implementation. In build 6 the
# content and cover contracts became O5.o and N5.o, both keyed as "o", removing
# content extraction when the null cover factory overwrote it.
# Other Readium code and the rest of the application remain optimized/obfuscated.
-keep,allowshrinking interface org.readium.r2.shared.publication.services.** { *; }
