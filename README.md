# Router-IPchecker

Предыстория
-----------
Мой интернет провайдер выдает IP адреса из пула публичных и приватных случайным образом. 
Т.е. один раз подключившись IP может быть публичным, а на следующий раз приватным.
Это сводит на нет радость от использования DDNS для подключения к локальной сети извне.

Решение
-------
Был написан данный скрипт, который, запускаясь через планировщик, подключается к роутеру по Telnet и проверяет IP.
Если IP приватный, то выполняется смена приоритета интернет подключения, что приводит к переподключению и получению нового IP от провайдера.
Процедура повторяется до получения публичного IP.

Может контролировать несколько подключений - задается через переменную %interfaces.
