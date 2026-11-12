'use strict';'require dom';'require fs';'require poll';'require uci';'require view';'require form';return view.extend({render:function(){var css=`
   #log_textarea pre {
    padding: 10px; /* 内边距 */
    border-bottom: 1px solid #ddd; /* 边框颜色 */
    font-size: small;
    line-height: 1.3; /* 行高 */
    white-space: pre-wrap;
    word-wrap: break-word;
    overflow-y: auto;
   }
   .cbi-section small {
    margin-left: 1rem;
    font-size: small; 
   }
   .log-container {
    display: flex;
    flex-direction: column;
    max-height: 1200px;
    overflow-y: auto;
    border-radius: 3px;
    margin-top: 10px;
    padding: 5px;
   }
   .log-line {
    padding: 3px 0;
    font-family: monospace;
    font-size: 12px;
    line-height: 1.4;
   }
   .log-line:last-child {
    border-bottom: none;
   }
   .log-timestamp {
    margin-right: 10px;
   }
  `;var log_container=E('div',{'class':'log-container','id':'log_container'},E('img',{'src':L.resource(['icons/loading.gif']),'alt':_('加载中…'),'style':'vertical-align:middle'},_('正在收集数据…')));var log_path='/var/log/timecontrol.log';var lastLogContent='';var lastScrollTop=0;var isScrolledToTop=true;function parseLogTimestamp(logLine){var timestampMatch=logLine.match(/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]/);if(timestampMatch){return new Date(timestampMatch[1]).getTime();}
return Date.now();}
function reverseLogLines(logContent){if(!logContent||logContent.trim()===''){return logContent;}
var lines=logContent.split('\n');lines=lines.filter(function(line){return line.trim()!=='';});lines.sort(function(a,b){var timeA=parseLogTimestamp(a);var timeB=parseLogTimestamp(b);return timeB-timeA;});return lines.join('\n');}
function formatLogLines(logContent,isNewContent){if(!logContent||logContent.trim()===''){return E('div',{'class':'log-line'},_('日志已清空。'));}
var lines=logContent.split('\n');var formattedLines=[];for(var i=0;i<lines.length;i++){var line=lines[i].trim();if(line==='')continue;var timestampMatch=line.match(/^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\]/);var timestampSpan=null;var messageSpan=null;var lineClass='log-line';if(timestampMatch){timestampSpan=E('span',{'class':'log-timestamp','title':timestampMatch[1]},timestampMatch[0]+' ');messageSpan=E('span',{},line.substring(timestampMatch[0].length+1));}else{messageSpan=E('span',{},line);}
var lineDiv=E('div',{'class':lineClass},[timestampSpan,messageSpan].filter(function(el){return el!==null;}));formattedLines.push(lineDiv);}
return E('div',{},formattedLines);}
var clear_log_button=E('div',{},[E('button',{'class':'cbi-button cbi-button-remove','click':function(ev){ev.preventDefault();var button=ev.target;button.disabled=true;button.textContent=_('清空日志...');fs.exec_direct('/usr/libexec/timecontrol-call',['clear_log']).then(function(){button.textContent=_('日志已成功清空！');button.disabled=false;button.textContent=_('清空日志');var logContent=_('日志已清空。');lastLogContent=logContent;dom.content(log_container,formatLogLines(logContent,false));isScrolledToTop=true;}).catch(function(){button.textContent=_('清空日志失败。');button.disabled=false;button.textContent=_('清空日志');});}},_('清空日志'))]);log_container.addEventListener('scroll',function(){lastScrollTop=this.scrollTop;isScrolledToTop=this.scrollTop<=1;});poll.add(L.bind(function(){return fs.read_direct(log_path,'text').then(function(res){var logContent=res.trim();if(logContent===''){logContent=_('日志已清空。');}
if(logContent!==lastLogContent){var isNewContent=lastLogContent!==''&&lastLogContent!==_('日志已清空。');var reversedLog=reverseLogLines(logContent);var formattedLog=formatLogLines(reversedLog,isNewContent);var prevScrollHeight=log_container.scrollHeight;var prevScrollTop=log_container.scrollTop;dom.content(log_container,formattedLog);lastLogContent=logContent;if(isScrolledToTop||isNewContent){log_container.scrollTop=0;}else{var newScrollHeight=log_container.scrollHeight;var heightDiff=newScrollHeight-prevScrollHeight;log_container.scrollTop=prevScrollTop+heightDiff;}}}).catch(function(err){var logContent;if(err.toString().includes('NotFoundError')){logContent=_('日志文件不存在。');}else{logContent=_('未知错误：%s').format(err);}
if(logContent!==lastLogContent){dom.content(log_container,formatLogLines(logContent,false));lastLogContent=logContent;}});}));poll.start();return E('div',{'class':'cbi-map'},[E('style',[css]),E('div',{'class':'cbi-section'},[clear_log_button,log_container,E('small',{},_('每 5 秒刷新。').format(L.env.pollinterval)),E('div',{'class':'cbi-section-actions cbi-section-actions-right'})]),E('div',{'style':'text-align: right;  font-style: italic;'},[E('span',{},[_('© github '),E('a',{'href':'https://github.com/sirpdboy','target':'_blank','style':'text-decoration: none;'},'by sirpdboy')])])]);},handleSaveApply:null,handleSave:null,handleReset:null});