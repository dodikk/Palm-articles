mkdir -p /var/etc/ipkg/
ln -s /etc/ipkg/arch.conf /var/etc/ipkg/
echo "src/gz all http://ipkg.preware.org/feeds/preware/all" > /var/etc/ipkg/preware.conf

echo "src/gz i686 http://ipkg.preware.org/feeds/preware/i686" >> /var/etc/ipkg/preware.conf

/usr/bin/ipkg -o /var update
/usr/bin/ipkg -o /var install x-webosinternals-termplugin
ln -s /var/usr/lib/BrowserPlugins/termplugin.so /usr/lib/BrowserPlugins/
/usr/bin/ipkg -o /var install org.webosinternals.terminal

#luna-send -n 1 palm://com.palm.applicationManager/rescan {}