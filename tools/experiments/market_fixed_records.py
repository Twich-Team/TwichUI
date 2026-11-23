"""Experimental fixed-width current tuples; no compression or general parser.

Every source character is hex or the unavailable sentinel z. Widths follow the
existing thirteen columns. This is NOT a negotiated production format.
"""
import re

WIDTHS=(8,64,1,10,10,10,14,1,1,10,2,2,2)
MAXIMUMS=(2147483647,None,4,99999999999,99999999999,99999999999,9007199254740991,0,1,99999999999,14,60,60)
NULLABLE={3,4,5,6,9}


def encode_rows(rows):
    output=[]
    for row in rows:
        if len(row)!=13:raise ValueError('current columns required')
        for i,(value,width,maximum)in enumerate(zip(row,WIDTHS,MAXIMUMS)):
            if value is None and i in NULLABLE:word='z'*width
            elif i==1:
                if type(value)is not str or not re.fullmatch('[0-9a-f]{64}',value):raise ValueError('exact variant')
                word=value
            else:
                if i in (3,4,5,9) and type(value)is str and re.fullmatch('[1-9][0-9]{0,10}',value):value=int(value)
                if type(value)is not int or not 0<=value<=maximum:raise ValueError('bounded integer')
                word=format(value,'0'+str(width)+'x')
            if len(word)!=width:raise ValueError('field width')
            output.append(word)
    return ''.join(output)
